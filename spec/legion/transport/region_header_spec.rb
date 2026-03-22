# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Transport::Message, 'region header injection' do
  let(:base_options) { { task_id: 'test-123', routing_key: 'test.route' } }

  describe 'when region is configured' do
    before { Legion::Settings[:transport][:region] = 'us-east-2' }
    after { Legion::Settings[:transport][:region] = nil }

    it 'injects x-legion-region header' do
      msg = described_class.new(**base_options)
      expect(msg.headers['x-legion-region']).to eq('us-east-2')
    end

    it 'injects x-legion-region-affinity defaulting to prefer_local' do
      msg = described_class.new(**base_options)
      expect(msg.headers['x-legion-region-affinity']).to eq('prefer_local')
    end

    it 'uses explicit region_affinity when provided' do
      msg = described_class.new(**base_options, region_affinity: 'require_local')
      expect(msg.headers['x-legion-region-affinity']).to eq('require_local')
    end

    it 'supports any affinity value' do
      msg = described_class.new(**base_options, region_affinity: 'any')
      expect(msg.headers['x-legion-region-affinity']).to eq('any')
    end
  end

  describe 'when region is nil' do
    before { Legion::Settings[:transport][:region] = nil }

    it 'does not inject x-legion-region header' do
      msg = described_class.new(**base_options)
      expect(msg.headers).not_to have_key('x-legion-region')
    end

    it 'does not inject x-legion-region-affinity header' do
      msg = described_class.new(**base_options)
      expect(msg.headers).not_to have_key('x-legion-region-affinity')
    end
  end

  describe 'preserves existing headers' do
    before { Legion::Settings[:transport][:region] = 'us-west-2' }
    after { Legion::Settings[:transport][:region] = nil }

    it 'still includes legion_protocol_version' do
      msg = described_class.new(**base_options)
      expect(msg.headers['legion_protocol_version']).to eq('2.0')
    end

    it 'still includes task_id in headers' do
      msg = described_class.new(**base_options)
      expect(msg.headers[:task_id]).to eq('test-123')
    end
  end
end
