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

    context 'channel leak prevention' do
      before do
        Legion::Settings[:transport][:tenant_topology] ||= {}
        Legion::Settings[:transport][:tenant_topology][:enabled] = true
      end

      after do
        Legion::Settings[:transport][:tenant_topology][:enabled] = false
      end

      it 'closes an internally-acquired channel even when provision raises' do
        owned_channel = instance_double('Bunny::Channel')
        allow(owned_channel).to receive(:topic).and_raise(StandardError, 'boom')
        allow(owned_channel).to receive(:fanout)
        allow(owned_channel).to receive(:respond_to?).with(:close).and_return(true)
        allow(owned_channel).to receive(:close)

        allow(Legion::Transport::Connection).to receive(:channel).and_return(owned_channel)

        expect(owned_channel).to receive(:close)
        expect { described_class.provision('abc123') }.to raise_error(StandardError, 'boom')
      end
    end
  end

  describe '.deprovision' do
    context 'when tenant_topology is disabled' do
      before do
        Legion::Settings[:transport][:tenant_topology] ||= {}
        Legion::Settings[:transport][:tenant_topology][:enabled] = false
      end

      it 'skips deprovision and does not raise' do
        expect { described_class.deprovision('abc123', channel: channel) }.not_to raise_error
      end

      it 'does not attempt to delete any exchanges' do
        expect(channel).not_to receive(:exchange_delete)
        described_class.deprovision('abc123', channel: channel)
      end
    end

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

      it 'skips deprovision when tenant_id is nil' do
        expect(channel).not_to receive(:exchange_delete)
        described_class.deprovision(nil, channel: channel)
      end

      it 'skips deprovision when tenant_id is blank' do
        expect(channel).not_to receive(:exchange_delete)
        described_class.deprovision('', channel: channel)
      end

      it 'skips deprovision when tenant_id is "default"' do
        expect(channel).not_to receive(:exchange_delete)
        described_class.deprovision('default', channel: channel)
      end
    end
  end

  describe 'EXCHANGE_TYPES constant' do
    it 'includes tasks, results, and events' do
      expect(described_class::EXCHANGE_TYPES).to contain_exactly('tasks', 'results', 'events')
    end
  end
end
