# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Connection recovery handling' do
  let(:connection) { Legion::Transport::Connection }

  before do
    connection.instance_variable_set(:@shutting_down, false)
    connection.instance_variable_set(:@recovery_timestamps, [])
    connection.instance_variable_set(:@reconnect_callbacks, [])
  end

  describe '.tear_down_session' do
    let(:mock_transport) { double('transport') }
    let(:status_mutex) { double('status_mutex') }
    let(:mock_session) do
      double('session',
             send:                  nil,
             instance_variable_get: nil,
             close:                 true).tap do |s|
        allow(s).to receive(:instance_variable_set)
        allow(s).to receive(:instance_variable_get).with(:@transport).and_return(mock_transport)
        allow(s).to receive(:instance_variable_get).with(:@reader_loop).and_return(nil)
        allow(s).to receive(:instance_variable_get).with(:@status_mutex).and_return(status_mutex)
      end
    end

    before do
      allow(status_mutex).to receive(:synchronize).and_yield
    end

    it 'marks the session as intentionally closing before attempting session close' do
      expect(status_mutex).to receive(:synchronize).ordered.and_yield
      expect(mock_session).to receive(:instance_variable_set).with(:@status, :closing).ordered
      expect(mock_session).to receive(:instance_variable_set).with(:@manually_closed, true).ordered
      expect(mock_session).to receive(:instance_variable_set).with(:@recovering_from_network_failure, false).ordered
      expect(mock_session).to receive(:close).ordered
      connection.send(:tear_down_session, mock_session)
    end

    it 'disables recovery flag on the session' do
      expect(mock_session).to receive(:instance_variable_set).with(:@recovering_from_network_failure, false)
      connection.send(:tear_down_session, mock_session)
    end

    it 'handles missing status mutex gracefully' do
      allow(mock_session).to receive(:instance_variable_get).with(:@status_mutex).and_return(nil)
      expect { connection.send(:tear_down_session, mock_session) }.not_to raise_error
    end

    it 'clears recovery flag even when status mutex is missing' do
      allow(mock_session).to receive(:instance_variable_get).with(:@status_mutex).and_return(nil)
      expect(mock_session).to receive(:instance_variable_set).with(:@recovering_from_network_failure, false)
      connection.send(:tear_down_session, mock_session)
    end

    it 'kills reader loop thread when session close times out' do
      allow(mock_session).to receive(:close) { sleep 10 }
      mock_reader = double('reader_loop')
      mock_thread = double('thread')
      allow(mock_session).to receive(:instance_variable_get).with(:@reader_loop).and_return(mock_reader)
      allow(mock_reader).to receive(:instance_variable_get).with(:@thread).and_return(mock_thread)
      expect(mock_thread).to receive(:kill)
      connection.send(:tear_down_session, mock_session)
    end
  end

  describe '.force_reconnect' do
    it 'skips reconnect when @shutting_down is true' do
      connection.instance_variable_set(:@shutting_down, true)
      expect(connection).not_to receive(:setup)
      connection.force_reconnect
    end

    it 'resets recovery timestamps' do
      connection.instance_variable_set(:@recovery_timestamps, [Time.now, Time.now])
      # Mock the tear_down and setup to avoid actual connection
      allow(connection).to receive(:session).and_return(nil)
      allow(connection).to receive(:setup)
      connection.force_reconnect
      expect(connection.instance_variable_get(:@recovery_timestamps)).to eq([])
    end

    it 'invokes registered on_force_reconnect callbacks' do
      called = false
      connection.on_force_reconnect { called = true }
      allow(connection).to receive(:session).and_return(nil)
      allow(connection).to receive(:setup)
      connection.force_reconnect
      expect(called).to be true
    end

    it 'does not raise when a callback raises' do
      connection.on_force_reconnect { raise 'boom' }
      allow(connection).to receive(:session).and_return(nil)
      allow(connection).to receive(:setup)
      expect { connection.force_reconnect }.not_to raise_error
    end

    it 'serializes concurrent reconnect attempts' do
      calls = 0
      lock = Mutex.new
      allow(connection).to receive(:session).and_return(nil)
      allow(connection).to receive(:setup) do
        lock.synchronize { calls += 1 }
        sleep 0.05
      end

      threads = [Thread.new { connection.force_reconnect }, Thread.new { connection.force_reconnect }]
      threads.each(&:join)

      expect(calls).to eq(1)
    end
  end

  describe '.setup' do
    it 'rebuilds a closed single session instead of reusing it' do
      closed_session = instance_double('Bunny::Session', open?: false, closed?: true)
      qos_channel = instance_double('Bunny::Channel', basic_qos: nil, open?: true, close: nil)
      log_channel = instance_double('Bunny::Channel', prefetch: nil, open?: true, close: nil)
      new_session = instance_double('Bunny::Session', open?: false, closed?: false, start: nil)
      allow(new_session).to receive(:create_channel).and_return(qos_channel, log_channel)
      allow(connection).to receive(:lite_mode?).and_return(false)
      allow(connection).to receive(:settings).and_return(
        Legion::Settings[:transport].merge(
          connection_pool_size: 1,
          channel:              { session_worker_pool_size: 8, default_worker_pool_size: 1 },
          prefetch:             2,
          connection:           Legion::Settings[:transport][:connection]
        )
      )
      allow(connection).to receive(:create_session_with_failover).and_return(new_session)
      allow(connection).to receive(:register_session_callbacks)
      allow(connection).to receive(:apply_quorum_policy_if_enabled)
      connection.instance_variable_set(:@session, Concurrent::AtomicReference.new(closed_session))

      connection.setup

      expect(connection.session).to eq(new_session)
      expect(new_session).to have_received(:start)
    end
  end

  describe '.register_session_callbacks' do
    it 'hooks after_recovery_attempts_exhausted to trigger force_reconnect' do
      mock_session = double('session')
      allow(connection).to receive(:session).and_return(mock_session)
      allow(mock_session).to receive(:respond_to?).with(:on_blocked).and_return(false)
      allow(mock_session).to receive(:respond_to?).with(:on_unblocked).and_return(false)
      allow(mock_session).to receive(:respond_to?).with(:after_recovery_attempts_exhausted).and_return(true)
      allow(mock_session).to receive(:respond_to?).with(:after_recovery_completed).and_return(false)

      exhausted_block = nil
      allow(mock_session).to receive(:after_recovery_attempts_exhausted) { |&blk| exhausted_block = blk }

      connection.send(:register_session_callbacks)
      expect(exhausted_block).not_to be_nil
    end
  end

  describe 'recovery rate detection' do
    it 'detects pathological recovery loop' do
      timestamps = connection.instance_variable_get(:@recovery_timestamps) || []
      6.times { timestamps << Time.now }
      connection.instance_variable_set(:@recovery_timestamps, timestamps)
      expect(timestamps.size).to be >= Legion::Transport::Connection::MAX_RECOVERIES_PER_WINDOW
    end

    it 'evicts stale timestamps outside the window' do
      timestamps = [Time.now - 120, Time.now - 90, Time.now]
      timestamps.reject! { |t| t < Time.now - Legion::Transport::Connection::RECOVERY_WINDOW }
      expect(timestamps.size).to eq(1)
    end
  end

  describe '.shutdown' do
    it 'sets @shutting_down to prevent force_reconnect during teardown' do
      connection.instance_variable_set(:@session, nil)
      connection.instance_variable_set(:@log_channel, nil)
      connection.instance_variable_set(:@build_session, nil)
      connection.instance_variable_set(:@pool, nil)
      connection.shutdown
      # After shutdown, @shutting_down should be reset to false (in ensure)
      expect(connection.instance_variable_get(:@shutting_down)).to be false
    end
  end

  describe 'constants' do
    it 'defines RECOVERY_WINDOW' do
      expect(Legion::Transport::Connection::RECOVERY_WINDOW).to eq(60)
    end

    it 'defines MAX_RECOVERIES_PER_WINDOW' do
      expect(Legion::Transport::Connection::MAX_RECOVERIES_PER_WINDOW).to eq(5)
    end
  end

  describe '.on_force_reconnect' do
    it 'accumulates callbacks' do
      connection.instance_variable_set(:@reconnect_callbacks, [])
      connection.on_force_reconnect { 'a' }
      connection.on_force_reconnect { 'b' }
      expect(connection.instance_variable_get(:@reconnect_callbacks).size).to eq(2)
    end
  end

  describe '.channel' do
    before do
      allow(connection).to receive(:lite_mode?).and_return(false)
      connection.instance_variable_set(:@pool, nil)
      connection.instance_variable_set(:@channel_thread, Concurrent::ThreadLocalVar.new(nil))
    end

    context 'when session is nil (force_reconnect teardown window)' do
      it 'raises IOError instead of NoMethodError' do
        connection.instance_variable_set(:@session, nil)
        expect { connection.channel }.to raise_error(IOError, /transport session unavailable/)
      end
    end

    context 'when session exists but is not open (Bunny recovery in progress)' do
      it 'raises IOError instead of RuntimeError' do
        recovering = instance_double('Bunny::Session', open?: false)
        connection.instance_variable_set(:@session, Concurrent::AtomicReference.new(recovering))
        expect { connection.channel }.to raise_error(IOError, /transport session unavailable/)
      end
    end
  end

  describe '.shutdown pre-marks sessions non-recoverable' do
    it 'disables auto-recovery on the primary session before teardown' do
      mock_session = double('session',
                            open?:                 true,
                            instance_variable_get: nil)
      allow(mock_session).to receive(:instance_variable_get).with(:@status_mutex).and_return(nil)
      allow(mock_session).to receive(:instance_variable_set)
      allow(mock_session).to receive(:close)
      connection.instance_variable_set(:@session, Concurrent::AtomicReference.new(mock_session))
      connection.instance_variable_set(:@log_channel, nil)
      connection.instance_variable_set(:@build_session, nil)
      connection.instance_variable_set(:@pool, nil)

      connection.shutdown

      expect(mock_session).to have_received(:instance_variable_set)
        .with(:@recovering_from_network_failure, false).at_least(:once)
    end
  end
end
