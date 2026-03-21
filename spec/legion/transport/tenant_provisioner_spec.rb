# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/tenant_provisioner'

RSpec.describe Legion::Transport::TenantProvisioner do
  let(:channel) { instance_double('Bunny::Channel') }

  describe '.provision' do
    context 'when tenant_topology is disabled (default)' do
      before do
        Legion::Settings[:transport][:tenant_topology] ||= {}
        Legion::Settings[:transport][:tenant_topology][:enabled] = false
        allow(channel).to receive(:topic)
        allow(channel).to receive(:fanout)
      end

      it 'creates exchanges with un-prefixed names' do
        expect(channel).to receive(:topic).with('tasks', durable: true)
        expect(channel).to receive(:topic).with('results', durable: true)
        expect(channel).to receive(:topic).with('events', durable: true)
        expect(channel).to receive(:fanout).with('dlx', durable: true)
        described_class.provision('abc123', channel: channel)
      end
    end

    context 'when tenant_topology is enabled' do
      before do
        Legion::Settings[:transport][:tenant_topology] ||= {}
        Legion::Settings[:transport][:tenant_topology][:enabled] = true
        allow(channel).to receive(:topic)
        allow(channel).to receive(:fanout)
      end

      after do
        Legion::Settings[:transport][:tenant_topology][:enabled] = false
      end

      it 'creates topic exchanges with tenant prefix' do
        expect(channel).to receive(:topic).with('t.abc123.tasks', durable: true)
        expect(channel).to receive(:topic).with('t.abc123.results', durable: true)
        expect(channel).to receive(:topic).with('t.abc123.events', durable: true)
        expect(channel).to receive(:fanout).with('t.abc123.dlx', durable: true)
        described_class.provision('abc123', channel: channel)
      end

      it 'does not close the channel when channel is provided' do
        expect(channel).not_to receive(:close)
        described_class.provision('abc123', channel: channel)
      end
    end
  end

  describe '.deprovision' do
    context 'when tenant_topology is enabled' do
      before do
        Legion::Settings[:transport][:tenant_topology] ||= {}
        Legion::Settings[:transport][:tenant_topology][:enabled] = true
        allow(channel).to receive(:exchange_delete)
      end

      after do
        Legion::Settings[:transport][:tenant_topology][:enabled] = false
      end

      it 'deletes all tenant-prefixed exchanges' do
        expect(channel).to receive(:exchange_delete).with('t.abc123.tasks')
        expect(channel).to receive(:exchange_delete).with('t.abc123.results')
        expect(channel).to receive(:exchange_delete).with('t.abc123.events')
        expect(channel).to receive(:exchange_delete).with('t.abc123.dlx')
        described_class.deprovision('abc123', channel: channel)
      end

      it 'does not raise when exchange_delete fails' do
        allow(channel).to receive(:exchange_delete).and_raise(StandardError, 'not found')
        expect { described_class.deprovision('abc123', channel: channel) }.not_to raise_error
      end

      it 'does not close the channel when channel is provided' do
        expect(channel).not_to receive(:close)
        described_class.deprovision('abc123', channel: channel)
      end
    end
  end

  describe 'EXCHANGE_TYPES constant' do
    it 'includes tasks, results, and events' do
      expect(described_class::EXCHANGE_TYPES).to contain_exactly('tasks', 'results', 'events')
    end
  end
end
