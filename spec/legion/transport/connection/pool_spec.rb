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
      create_channel: instance_double('Bunny::Channel', basic_qos: nil, open?: true, close: nil)
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
  end

  describe 'connection pool activation' do
    context 'when connection_pool_size is 1 (default)' do
      before do
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
    end
  end
end
