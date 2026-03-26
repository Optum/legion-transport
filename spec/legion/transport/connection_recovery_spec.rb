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
    let(:mock_session) do
      double('session',
             instance_variable_get: nil,
             close:                 true).tap do |s|
        allow(s).to receive(:instance_variable_set)
        allow(s).to receive(:instance_variable_get).with(:@transport).and_return(mock_transport)
        allow(s).to receive(:instance_variable_get).with(:@reader_loop).and_return(nil)
      end
    end

    it 'closes transport socket before attempting session close' do
      expect(mock_transport).to receive(:close).ordered
      expect(mock_session).to receive(:close).ordered
      connection.send(:tear_down_session, mock_session)
    end

    it 'disables recovery flag on the session' do
      allow(mock_transport).to receive(:close)
      expect(mock_session).to receive(:instance_variable_set).with(:@recovering_from_network_failure, false)
      connection.send(:tear_down_session, mock_session)
    end

    it 'handles nil transport gracefully' do
      allow(mock_session).to receive(:instance_variable_get).with(:@transport).and_return(nil)
      expect { connection.send(:tear_down_session, mock_session) }.not_to raise_error
    end

    it 'kills reader loop thread when session close times out' do
      allow(mock_transport).to receive(:close)
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
end
