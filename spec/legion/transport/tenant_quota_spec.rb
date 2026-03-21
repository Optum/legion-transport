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
  end

  describe 'QuotaExceededError' do
    it 'is a subclass of StandardError' do
      expect(described_class::QuotaExceededError.ancestors).to include(StandardError)
    end
  end
end
