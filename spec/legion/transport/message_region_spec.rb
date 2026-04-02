# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Transport::Message, 'Legion::Region header stamping' do
  let(:base_options) { { task_id: 'task-abc', routing_key: 'test.route' } }

  describe 'when Legion::Region is defined and current returns a value' do
    before do
      stub_const('Legion::Region', Module.new)
      allow(Legion::Region).to receive(:current).and_return('us-east-2')
    end

    it 'stamps the region header' do
      msg = described_class.new(**base_options)
      expect(msg.headers['region']).to eq('us-east-2')
    end

    it 'defaults region_affinity to prefer_local' do
      msg = described_class.new(**base_options)
      expect(msg.headers['region_affinity']).to eq('prefer_local')
    end

    it 'uses per-message region_affinity override' do
      msg = described_class.new(**base_options, region_affinity: 'require_local')
      expect(msg.headers['region_affinity']).to eq('require_local')
    end

    it 'uses Settings default_affinity when no per-message override is given' do
      allow(Legion::Settings).to receive(:dig).and_call_original
      allow(Legion::Settings).to receive(:dig).with(:region, :default_affinity).and_return('nearest')
      msg = described_class.new(**base_options)
      expect(msg.headers['region_affinity']).to eq('nearest')
    end

    it 'per-message override takes priority over Settings default_affinity' do
      allow(Legion::Settings).to receive(:dig).and_call_original
      allow(Legion::Settings).to receive(:dig).with(:region, :default_affinity).and_return('nearest')
      msg = described_class.new(**base_options, region_affinity: 'any')
      expect(msg.headers['region_affinity']).to eq('any')
    end

    it 'still includes legion_protocol_version alongside region header' do
      msg = described_class.new(**base_options)
      expect(msg.headers['legion_protocol_version']).to eq('2.0')
    end

    it 'still propagates task_id into headers' do
      msg = described_class.new(**base_options)
      expect(msg.headers[:task_id]).to eq('task-abc')
    end

    it 'only resolves the current region once per header build' do
      msg = described_class.new(**base_options)
      msg.headers
      expect(Legion::Region).to have_received(:current).once
    end
  end

  describe 'when Legion::Region is not defined' do
    before do
      hide_const('Legion::Region') if defined?(Legion::Region)
    end

    it 'does not stamp the region header' do
      msg = described_class.new(**base_options)
      expect(msg.headers).not_to have_key('region')
    end

    it 'does not stamp the region_affinity header' do
      msg = described_class.new(**base_options)
      expect(msg.headers).not_to have_key('region_affinity')
    end
  end

  describe 'when Legion::Region.current returns nil' do
    before do
      stub_const('Legion::Region', Module.new)
      allow(Legion::Region).to receive(:current).and_return(nil)
    end

    it 'does not stamp the region header' do
      msg = described_class.new(**base_options)
      expect(msg.headers).not_to have_key('region')
    end

    it 'does not stamp the region_affinity header' do
      msg = described_class.new(**base_options)
      expect(msg.headers).not_to have_key('region_affinity')
    end
  end

  describe 'when default affinity is any and no explicit region is configured' do
    before do
      stub_const('Legion::Region', Module.new)
      allow(Legion::Region).to receive(:current).and_return('us-east-2')
      allow(Legion::Settings).to receive(:dig).with(:region, :default_affinity).and_return('any')
      allow(Legion::Settings).to receive(:dig).with(:region, :current).and_return(nil)
    end

    it 'does not resolve Legion::Region.current' do
      msg = described_class.new(**base_options)
      expect(msg.headers).not_to have_key('region')
      expect(msg.headers).not_to have_key('region_affinity')
      expect(Legion::Region).not_to have_received(:current)
    end
  end

  describe 'standalone mode (no Legion::Region, no Legion::Settings region config)' do
    before do
      hide_const('Legion::Region') if defined?(Legion::Region)
    end

    it 'adds no region headers and does not raise' do
      msg = described_class.new(**base_options)
      expect { msg.headers }.not_to raise_error
      expect(msg.headers).not_to have_key('region')
      expect(msg.headers).not_to have_key('region_affinity')
    end

    it 'still sets legion_protocol_version' do
      msg = described_class.new(**base_options)
      expect(msg.headers['legion_protocol_version']).to eq('2.0')
    end
  end
end
