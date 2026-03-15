# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/queues/node_crypt'

RSpec.describe Legion::Transport::Queues::NodeCrypt do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Queue' do
    expect(described_class.ancestors).to include(Legion::Transport::Queue)
  end

  it 'is defined under Legion::Transport::Queues' do
    expect(described_class.name).to eq 'Legion::Transport::Queues::NodeCrypt'
  end

  it 'returns the correct queue name' do
    instance = described_class.allocate
    expect(instance.queue_name).to eq 'node.crypt'
  end

  it 'returns queue options with durable: true and manual_ack: true' do
    instance = described_class.allocate
    options = instance.queue_options
    expect(options[:durable]).to eq true
    expect(options[:manual_ack]).to eq true
    expect(options[:exclusive]).to eq false
    expect(options[:block]).to eq false
  end

  it 'includes the node dead-letter exchange in queue options' do
    instance = described_class.allocate
    dlx = instance.queue_options.dig(:arguments, :'x-dead-letter-exchange')
    expect(dlx).to eq 'node.dlx'
  end
end
