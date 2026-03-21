# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/tenant_topology'

RSpec.describe Legion::Transport::TenantTopology do
  before do
    Legion::Settings[:transport][:tenant_topology] ||= {}
    Legion::Settings[:transport][:tenant_topology][:enabled] = false
  end

  after do
    Legion::Settings[:transport][:tenant_topology][:enabled] = false
  end

  describe '.enabled?' do
    context 'when disabled (default)' do
      it 'returns false' do
        expect(described_class.enabled?).to be false
      end
    end

    context 'when enabled via settings' do
      before { Legion::Settings[:transport][:tenant_topology][:enabled] = true }

      it 'returns true' do
        expect(described_class.enabled?).to be true
      end
    end
  end

  describe '.shared?' do
    it 'returns true for legion.control prefix' do
      expect(described_class.shared?('legion.control')).to be true
      expect(described_class.shared?('legion.control.sub')).to be true
    end

    it 'returns true for legion.health prefix' do
      expect(described_class.shared?('legion.health')).to be true
    end

    it 'returns true for legion.audit prefix' do
      expect(described_class.shared?('legion.audit')).to be true
    end

    it 'returns false for non-shared names' do
      expect(described_class.shared?('tasks')).to be false
      expect(described_class.shared?('results')).to be false
    end
  end

  describe '.exchange_name' do
    context 'when disabled' do
      it 'passes name through unchanged regardless of tenant_id' do
        expect(described_class.exchange_name('tasks', tenant_id: 'abc123')).to eq('tasks')
      end

      it 'passes name through unchanged with no tenant_id' do
        expect(described_class.exchange_name('tasks')).to eq('tasks')
      end
    end

    context 'when enabled' do
      before { Legion::Settings[:transport][:tenant_topology][:enabled] = true }

      it 'prefixes with tenant_id when provided' do
        expect(described_class.exchange_name('tasks', tenant_id: 'abc123')).to eq('t.abc123.tasks')
      end

      it 'returns base name when tenant_id is nil' do
        expect(described_class.exchange_name('tasks', tenant_id: nil)).to eq('tasks')
      end

      it 'returns base name when tenant_id is "default"' do
        expect(described_class.exchange_name('tasks', tenant_id: 'default')).to eq('tasks')
      end

      it 'does not prefix shared exchanges' do
        expect(described_class.exchange_name('legion.control', tenant_id: 'abc123')).to eq('legion.control')
        expect(described_class.exchange_name('legion.health', tenant_id: 'abc123')).to eq('legion.health')
        expect(described_class.exchange_name('legion.audit', tenant_id: 'abc123')).to eq('legion.audit')
      end

      it 'does not prefix shared exchange subnames' do
        expect(described_class.exchange_name('legion.control.something', tenant_id: 'abc123')).to eq('legion.control.something')
      end
    end
  end

  describe '.queue_name' do
    context 'when disabled' do
      it 'passes name through unchanged regardless of tenant_id' do
        expect(described_class.queue_name('my.queue', tenant_id: 'abc123')).to eq('my.queue')
      end
    end

    context 'when enabled' do
      before { Legion::Settings[:transport][:tenant_topology][:enabled] = true }

      it 'prefixes with tenant_id when provided' do
        expect(described_class.queue_name('my.queue', tenant_id: 'abc123')).to eq('t.abc123.my.queue')
      end

      it 'returns base name when tenant_id is nil' do
        expect(described_class.queue_name('my.queue', tenant_id: nil)).to eq('my.queue')
      end

      it 'returns base name when tenant_id is "default"' do
        expect(described_class.queue_name('my.queue', tenant_id: 'default')).to eq('my.queue')
      end
    end
  end

  describe '.current_tenant_id' do
    context 'when Legion::TenantContext is not defined' do
      it 'returns nil' do
        expect(described_class.current_tenant_id).to be_nil
      end
    end

    context 'when Legion::TenantContext is defined' do
      before do
        stub_const('Legion::TenantContext', Module.new do
          def self.current_tenant_id
            'ctx123'
          end
        end)
      end

      it 'delegates to Legion::TenantContext.current_tenant_id' do
        expect(described_class.current_tenant_id).to eq('ctx123')
      end
    end

    context 'when Legion::TenantContext raises' do
      before do
        stub_const('Legion::TenantContext', Module.new do
          def self.current_tenant_id
            raise StandardError, 'context error'
          end
        end)
      end

      it 'returns nil' do
        expect(described_class.current_tenant_id).to be_nil
      end
    end
  end

  describe '.exchange_name with current_tenant_id fallback' do
    context 'when enabled and TenantContext provides tenant_id' do
      before do
        Legion::Settings[:transport][:tenant_topology][:enabled] = true
        stub_const('Legion::TenantContext', Module.new do
          def self.current_tenant_id
            'ctx456'
          end
        end)
      end

      it 'uses current_tenant_id when no explicit tenant_id given' do
        expect(described_class.exchange_name('tasks')).to eq('t.ctx456.tasks')
      end

      it 'uses explicit tenant_id over current_tenant_id' do
        expect(described_class.exchange_name('tasks', tenant_id: 'override')).to eq('t.override.tasks')
      end
    end
  end
end
