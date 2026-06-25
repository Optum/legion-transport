# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Transport::Message, 'identity header injection' do
  let(:base_options) { { task_id: 'task-xyz', routing_key: 'test.route' } }

  let(:identity_hash) do
    {
      canonical_name: 'node.example.com',
      id:             'ident-001',
      kind:           'process',
      mode:           'service',
      source:         'lex-identity-system'
    }
  end

  describe 'when Legion::Identity::Process is defined and resolved' do
    before do
      identity_mod = Module.new do
        def self.resolved? = true
      end
      stub_const('Legion::Identity::Process', identity_mod)
      allow(Legion::Identity::Process).to receive(:identity_hash).and_return(identity_hash)
    end

    it 'injects x-legion-identity-canonical-name' do
      msg = described_class.new(**base_options)
      expect(msg.headers['x-legion-identity-canonical-name']).to eq('node.example.com')
    end

    it 'injects x-legion-identity-id' do
      msg = described_class.new(**base_options)
      expect(msg.headers['x-legion-identity-id']).to eq('ident-001')
    end

    it 'injects x-legion-identity-kind' do
      msg = described_class.new(**base_options)
      expect(msg.headers['x-legion-identity-kind']).to eq('process')
    end

    it 'injects x-legion-identity-mode' do
      msg = described_class.new(**base_options)
      expect(msg.headers['x-legion-identity-mode']).to eq('service')
    end

    it 'injects x-legion-identity-source' do
      msg = described_class.new(**base_options)
      expect(msg.headers['x-legion-identity-source']).to eq('lex-identity-system')
    end

    it 'coerces nil identity fields to empty string' do
      allow(Legion::Identity::Process).to receive(:identity_hash).and_return(
        canonical_name: nil, id: nil, kind: nil, mode: nil, source: nil
      )
      msg = described_class.new(**base_options)
      expect(msg.headers['x-legion-identity-canonical-name']).to eq('')
      expect(msg.headers['x-legion-identity-id']).to eq('')
    end

    it 'preserves existing headers alongside identity headers' do
      msg = described_class.new(**base_options)
      hdrs = msg.headers
      expect(hdrs['legion_protocol_version']).to eq('2.0')
      expect(hdrs[:task_id]).to eq('task-xyz')
      expect(hdrs['x-legion-identity-id']).to eq('ident-001')
    end
  end

  describe 'when Legion::Identity::Process is defined but not resolved' do
    before do
      identity_mod = Module.new do
        def self.resolved? = false
      end
      stub_const('Legion::Identity::Process', identity_mod)
      allow(identity_mod).to receive(:identity_hash)
    end

    it 'does not inject identity headers' do
      msg = described_class.new(**base_options)
      hdrs = msg.headers
      expect(hdrs.keys).not_to include('x-legion-identity-canonical-name')
      expect(hdrs.keys).not_to include('x-legion-identity-id')
      expect(hdrs.keys).not_to include('x-legion-identity-kind')
      expect(hdrs.keys).not_to include('x-legion-identity-mode')
      expect(hdrs.keys).not_to include('x-legion-identity-source')
    end

    it 'does not call identity_hash when not resolved' do
      msg = described_class.new(**base_options)
      msg.headers
      expect(Legion::Identity::Process).not_to have_received(:identity_hash)
    end
  end

  describe 'when Legion::Identity::Process is not defined' do
    before do
      hide_const('Legion::Identity::Process') if defined?(Legion::Identity::Process)
    end

    it 'does not inject identity headers' do
      msg = described_class.new(**base_options)
      hdrs = msg.headers
      expect(hdrs.keys).not_to include('x-legion-identity-canonical-name')
      expect(hdrs.keys).not_to include('x-legion-identity-id')
    end

    it 'does not raise' do
      msg = described_class.new(**base_options)
      expect { msg.headers }.not_to raise_error
    end

    it 'still sets legion_protocol_version' do
      msg = described_class.new(**base_options)
      expect(msg.headers['legion_protocol_version']).to eq('2.0')
    end
  end

  describe 'when identity_hash raises an exception' do
    before do
      identity_mod = Module.new do
        def self.resolved? = true

        def self.identity_hash
          raise 'identity resolution failed'
        end
      end
      stub_const('Legion::Identity::Process', identity_mod)
    end

    it 'does not raise (exception is rescued)' do
      msg = described_class.new(**base_options)
      expect { msg.headers }.not_to raise_error
    end

    it 'preserves existing headers built before the exception' do
      msg = described_class.new(**base_options)
      hdrs = msg.headers
      expect(hdrs['legion_protocol_version']).to eq('2.0')
    end

    it 'does not inject partial identity headers' do
      msg = described_class.new(**base_options)
      hdrs = msg.headers
      expect(hdrs.keys).not_to include('x-legion-identity-canonical-name')
    end
  end
end
