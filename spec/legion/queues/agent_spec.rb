# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/queues/agent'

RSpec.describe Legion::Transport::Queues::Agent do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Queue' do
    expect(described_class.ancestors).to include(Legion::Transport::Queue)
  end

  it 'is defined under Legion::Transport::Queues' do
    expect(described_class.name).to eq 'Legion::Transport::Queues::Agent'
  end

  it 'returns queue options with durable: false and auto_delete: true' do
    instance = described_class.allocate
    options = instance.queue_options
    expect(options[:durable]).to eq false
    expect(options[:auto_delete]).to eq true
  end

  it 'includes the agent dead-letter exchange in queue options' do
    instance = described_class.allocate
    dlx = instance.queue_options.dig(:arguments, :'x-dead-letter-exchange')
    expect(dlx).to eq 'agent.dlx'
  end

  it 'returns a queue name scoped to the provided agent_id' do
    instance = described_class.allocate
    instance.instance_variable_set(:@agent_id, 'abc-123')
    expect(instance.queue_name).to eq 'agent.abc-123'
  end

  it 'falls back to client name when no agent_id is set' do
    instance = described_class.allocate
    instance.instance_variable_set(:@agent_id, nil)
    allow(Legion::Settings).to receive(:[]).with('client').and_return({ 'name' => 'testnode' })
    expect(instance.queue_name).to eq 'agent.testnode'
  end

  it 'uses classic queue type (not quorum)' do
    instance = described_class.allocate
    expect(instance.queue_options.dig(:arguments, :'x-queue-type')).to eq('classic')
  end

  it 'is not durable' do
    instance = described_class.allocate
    expect(instance.queue_options[:durable]).to be false
  end
end
