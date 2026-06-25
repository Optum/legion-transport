# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/messages/region_re_route'

RSpec.describe Legion::Transport::Messages::RegionReRoute do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Message' do
    expect(described_class.ancestors).to include(Legion::Transport::Message)
  end

  it 'is defined under Legion::Transport::Messages' do
    expect(described_class.name).to eq 'Legion::Transport::Messages::RegionReRoute'
  end

  describe '#exchange' do
    it 'returns the Task exchange class' do
      instance = described_class.allocate
      expect(instance.exchange).to eq Legion::Transport::Exchanges::Task
    end
  end

  describe '#routing_key' do
    it 'returns the region reroute routing key for the target region' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { target_region: 'us-east-1' })
      expect(instance.routing_key).to eq 'region.reroute.us-east-1'
    end

    it 'includes the target region in the routing key' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { target_region: 'eu-west-2' })
      expect(instance.routing_key).to include('eu-west-2')
    end

    it 'uses the region.reroute prefix' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { target_region: 'ap-southeast-1' })
      expect(instance.routing_key).to start_with('region.reroute.')
    end
  end

  describe '#message' do
    let(:instance) { described_class.allocate }

    before do
      instance.instance_variable_set(:@options, {
                                       target_region:    'us-east-1',
                                       source_region:    'eu-west-2',
                                       original_payload: { function: 'do_thing' }
                                     })
    end

    it 'includes target_region' do
      expect(instance.message[:target_region]).to eq 'us-east-1'
    end

    it 'includes source_region' do
      expect(instance.message[:source_region]).to eq 'eu-west-2'
    end

    it 'includes original_payload' do
      expect(instance.message[:original_payload]).to eq({ function: 'do_thing' })
    end

    it 'includes rerouted_at timestamp' do
      expect(instance.message[:rerouted_at]).to be_an Integer
    end
  end

  describe '#validate' do
    it 'sets @valid to true when target_region is a non-empty string' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { target_region: 'us-east-1' })
      instance.validate
      expect(instance.instance_variable_get(:@valid)).to eq true
    end

    it 'raises ArgumentError when target_region is missing' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, {})
      expect { instance.validate }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError when target_region is not a String' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { target_region: 42 })
      expect { instance.validate }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError when target_region is an empty string' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { target_region: '' })
      expect { instance.validate }.to raise_error(ArgumentError)
    end
  end
end
