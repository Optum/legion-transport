# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/helpers/pool'

RSpec.describe Legion::Transport::Connection do
  let(:fake_session) do
    instance_double(
      'Bunny::Session',
      open?:          true,
      closed?:        false,
      close:          nil,
      start:          nil,
      create_channel: instance_double('Bunny::Channel', basic_qos: nil, open?: true, close: nil, prefetch: nil)
    )
  end

  before do
    # Reset pool state between tests
    described_class.instance_variable_set(:@pool, nil)
    described_class.instance_variable_set(:@session, nil)
  end

  after do
    described_class.instance_variable_set(:@pool, nil)
    described_class.instance_variable_set(:@session, nil)
    described_class.instance_variable_set(:@log_channel, nil)
  end

  describe 'connection pool activation' do
    context 'when connection_pool_size is 1 (default)' do
      before do
        allow(Legion::Settings).to receive(:[]).and_call_original
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          Legion::Settings[:transport].merge(connection_pool_size: 1)
        )
      end

      it 'does not instantiate a Pool' do
        expect(Legion::Transport::Helpers::Pool).not_to receive(:new)
        # verify pool is nil after setup in normal mode
        expect(described_class.instance_variable_get(:@pool)).to be_nil
      end
    end

    context 'when connection_pool_size > 1' do
      let(:pool_size) { 3 }

      before do
        allow(Legion::Settings).to receive(:[]).and_call_original
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          Legion::Settings[:transport].merge(connection_pool_size: pool_size)
        )
        allow(described_class).to receive(:create_session_with_failover).and_return(fake_session)
        allow(described_class).to receive(:register_session_callbacks)
        allow(described_class).to receive(:apply_quorum_policy_if_enabled)
        allow(described_class).to receive(:lite_mode?).and_return(false)
        allow(described_class).to receive(:settings).and_return(
          Legion::Settings[:transport].merge(
            connection_pool_size: pool_size,
            channel:              { session_worker_pool_size: 8, default_worker_pool_size: 1 },
            prefetch:             2
          )
        )
      end

      it 'creates a Pool with the configured size' do
        expect(Legion::Transport::Helpers::Pool).to receive(:new).with(size: pool_size).and_call_original
        described_class.setup
      end

      it 'sets @pool after setup' do
        described_class.setup
        expect(described_class.instance_variable_get(:@pool)).to be_a(Legion::Transport::Helpers::Pool)
      end

      it 'replaces a stale existing pool and primary session' do
        old_primary = instance_double('Bunny::Session', open?: false, closed?: true)
        old_pool = instance_double(Legion::Transport::Helpers::Pool, connected?: false, shutdown: nil)
        described_class.instance_variable_set(:@pool, old_pool)
        described_class.instance_variable_set(:@configured_pool_size, pool_size)
        described_class.instance_variable_set(:@session, Concurrent::AtomicReference.new(old_primary))

        described_class.setup

        expect(old_pool).to have_received(:shutdown)
        expect(described_class.session).to eq(fake_session)
      end

      it 'channel_open? delegates to session_open? in pool mode' do
        described_class.setup
        allow(described_class).to receive(:session_open?).and_return(true)
        expect(described_class.channel_open?).to be true
      end

      it 'channel_open? returns false in pool mode when session is closed' do
        described_class.setup
        allow(described_class).to receive(:session_open?).and_return(false)
        expect(described_class.channel_open?).to be false
      end

      it 'starts pooled sessions before creating a channel' do
        pooled_channel = instance_double('Bunny::Channel', prefetch: nil)
        pooled_session = instance_double('Bunny::Session', open?: false, start: nil, create_channel: pooled_channel)
        pool = instance_double(Legion::Transport::Helpers::Pool, checkout: pooled_session, checkin: nil)
        described_class.instance_variable_set(:@pool, pool)

        expect(pooled_session).to receive(:start).ordered
        expect(pooled_session).to receive(:create_channel).ordered.and_return(pooled_channel)
        expect(pooled_channel).to receive(:prefetch).with(2).ordered
        expect(pool).to receive(:checkin).with(pooled_session)

        expect(described_class.channel).to eq(pooled_channel)
      end

      it 'checks pooled sessions back in when channel creation fails' do
        pooled_session = instance_double('Bunny::Session', open?: true, start: nil)
        pool = instance_double(Legion::Transport::Helpers::Pool, checkout: pooled_session, checkin: nil)
        described_class.instance_variable_set(:@pool, pool)
        allow(pooled_session).to receive(:create_channel).and_raise(StandardError, 'boom')
        allow(described_class).to receive(:handle_exception)

        expect(pool).to receive(:checkin).with(pooled_session)
        expect { described_class.channel }.to raise_error(StandardError, 'boom')
      end
    end
  end
end
