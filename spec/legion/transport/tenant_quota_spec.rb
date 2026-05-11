# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/tenant_quota'

RSpec.describe Legion::Transport::TenantQuota do
  before do
    Legion::Settings[:transport][:tenant_topology] ||= {}
    Legion::Settings[:transport][:tenant_topology][:enabled] = false
    described_class.reset!
  end

  after do
    Legion::Settings[:transport][:tenant_topology][:enabled] = false
    described_class.reset!
  end

  describe '.enabled?' do
    it 'returns false when tenant_topology is disabled' do
      expect(described_class.enabled?).to be false
    end

    it 'returns true when tenant_topology is enabled' do
      Legion::Settings[:transport][:tenant_topology][:enabled] = true
      expect(described_class.enabled?).to be true
    end
  end

  describe '.check_publish' do
    context 'when disabled' do
      it 'always returns true regardless of call count' do
        100.times { expect(described_class.check_publish('abc123')).to be true }
      end

      it 'returns true even with message_size' do
        expect(described_class.check_publish('abc123', message_size: 10_000)).to be true
      end
    end

    context 'when enabled but no quota configured' do
      before { Legion::Settings[:transport][:tenant_topology][:enabled] = true }

      it 'returns true (no limit)' do
        100.times { expect(described_class.check_publish('abc123')).to be true }
      end
    end

    context 'when enabled with a messages_per_second quota' do
      before do
        Legion::Settings[:transport][:tenant_topology][:enabled] = true
        Legion::Settings[:transport][:tenant_topology][:quotas] = {
          abc123: { messages_per_second: 3 }
        }
      end

      it 'allows messages within quota' do
        3.times { expect(described_class.check_publish('abc123')).to be true }
      end

      it 'raises QuotaExceededError when over limit' do
        3.times { described_class.check_publish('abc123') }
        expect { described_class.check_publish('abc123') }
          .to raise_error(Legion::Transport::TenantQuota::QuotaExceededError, /abc123/)
      end

      it 'does not affect other tenants' do
        3.times { described_class.check_publish('abc123') }
        expect(described_class.check_publish('def456')).to be true
      end

      it 'resets counter on new time window' do
        3.times { described_class.check_publish('abc123') }
        allow(described_class).to receive(:current_window).and_return(999_999)
        expect(described_class.check_publish('abc123')).to be true
      end
    end

    context 'when enabled with a bytes_per_second quota' do
      before do
        Legion::Settings[:transport][:tenant_topology][:enabled] = true
        Legion::Settings[:transport][:tenant_topology][:quotas] = {
          abc123: { bytes_per_second: 100 }
        }
      end

      it 'allows messages within byte quota' do
        expect(described_class.check_publish('abc123', message_size: 50)).to be true
        expect(described_class.check_publish('abc123', message_size: 49)).to be true
      end

      it 'raises QuotaExceededError when byte limit exceeded' do
        described_class.check_publish('abc123', message_size: 50)
        described_class.check_publish('abc123', message_size: 49)
        expect { described_class.check_publish('abc123', message_size: 2) }
          .to raise_error(Legion::Transport::TenantQuota::QuotaExceededError)
      end
    end

    context 'per-tenant isolation (independent mutexes)' do
      before do
        Legion::Settings[:transport][:tenant_topology][:enabled] = true
        Legion::Settings[:transport][:tenant_topology][:quotas] = {
          tenant_a: { messages_per_second: 2 },
          tenant_b: { messages_per_second: 2 }
        }
      end

      it 'exhausting one tenant does not block another' do
        2.times { described_class.check_publish('tenant_a') }
        expect { described_class.check_publish('tenant_a') }
          .to raise_error(described_class::QuotaExceededError)
        expect(described_class.check_publish('tenant_b')).to be true
      end
    end
  end

  describe 'stale entry sweep' do
    before do
      Legion::Settings[:transport][:tenant_topology][:enabled] = true
      Legion::Settings[:transport][:tenant_topology][:quotas] = {
        stale_tenant: { messages_per_second: 100 }
      }
    end

    it 'removes entries that have not been updated within STALE_SECONDS' do
      described_class.check_publish('stale_tenant')

      # Simulate the entry being very old by backdating updated_at
      stale_window = described_class.send(:current_window) - (described_class::STALE_SECONDS + 1)
      described_class.instance_variable_get(:@counters)['stale_tenant'][:updated_at] = stale_window

      # Trigger sweep by making another call for a different tenant
      allow(Legion::Settings).to receive(:dig)
        .with(:transport, :tenant_topology, :quotas, :other_tenant)
        .and_return({ messages_per_second: 100 })
      described_class.check_publish('other_tenant')

      expect(described_class.instance_variable_get(:@counters)).not_to have_key('stale_tenant')
    end
  end

  describe '.reset!' do
    it 'clears all counters' do
      Legion::Settings[:transport][:tenant_topology][:enabled] = true
      Legion::Settings[:transport][:tenant_topology][:quotas] = {
        abc123: { messages_per_second: 1 }
      }
      described_class.check_publish('abc123')
      described_class.reset!
      expect(described_class.check_publish('abc123')).to be true
    end

    it 'clears per-tenant mutexes' do
      Legion::Settings[:transport][:tenant_topology][:enabled] = true
      Legion::Settings[:transport][:tenant_topology][:quotas] = {
        abc123: { messages_per_second: 10 }
      }
      described_class.check_publish('abc123')
      described_class.reset!
      expect(described_class.instance_variable_get(:@mutexes)).to be_empty
    end
  end

  describe 'QuotaExceededError' do
    it 'is a subclass of StandardError' do
      expect(described_class::QuotaExceededError.ancestors).to include(StandardError)
    end
  end
end
