# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Transport::Settings, 'cluster keys' do
  describe '.default' do
    subject(:defaults) { described_class.default }

    it 'includes cluster_nodes defaulting to empty array' do
      expect(defaults[:cluster_nodes]).to eq([])
    end

    it 'includes connection_pool_size defaulting to 1' do
      expect(defaults[:connection_pool_size]).to eq(1)
    end

    it 'includes region defaulting to nil' do
      expect(defaults[:region]).to be_nil
    end

    it 'includes management_port defaulting to 15672' do
      expect(defaults[:management_port]).to eq(15_672)
    end

    it 'includes quorum_queue_policy hash' do
      expect(defaults[:quorum_queue_policy]).to be_a(Hash)
    end

    it 'has quorum_queue_policy.enabled defaulting to false' do
      expect(defaults[:quorum_queue_policy][:enabled]).to eq false
    end

    it 'has quorum_queue_policy.pattern defaulting to ^legion\\.' do
      expect(defaults[:quorum_queue_policy][:pattern]).to eq('^legion\\.')
    end

    it 'has quorum_queue_policy.delivery_limit defaulting to 5' do
      expect(defaults[:quorum_queue_policy][:delivery_limit]).to eq(5)
    end
  end

  describe '.connection' do
    subject(:conn) { described_class.connection }

    it 'has connection_timeout defaulting to 10' do
      expect(conn[:connection_timeout]).to eq(10)
    end

    it 'has network_recovery_interval defaulting to 2' do
      expect(conn[:network_recovery_interval]).to eq(2)
    end

    it 'has heartbeat defaulting to 30' do
      expect(conn[:heartbeat]).to eq(30)
    end
  end

  describe 'cluster_nodes from env' do
    around do |example|
      old = ENV.fetch('transport.cluster_nodes', nil)
      ENV['transport.cluster_nodes'] = 'rmq2:5672,rmq3:5672'
      example.run
      old ? ENV['transport.cluster_nodes'] = old : ENV.delete('transport.cluster_nodes')
    end

    it 'parses comma-separated cluster_nodes from env' do
      defaults = described_class.default
      expect(defaults[:cluster_nodes]).to eq(%w[rmq2:5672 rmq3:5672])
    end
  end
end
