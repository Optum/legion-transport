# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/queues/node'

RSpec.describe Legion::Transport::Queues::Node do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Queue' do
    expect(described_class.ancestors).to include(Legion::Transport::Queue)
  end

  it 'is defined under Legion::Transport::Queues' do
    expect(described_class.name).to eq 'Legion::Transport::Queues::Node'
  end

  it 'returns queue options with durable: false and auto_delete: true' do
    instance = described_class.allocate
    options = instance.queue_options
    expect(options[:durable]).to eq false
    expect(options[:auto_delete]).to eq true
  end

  it 'includes the node dead-letter exchange in queue options' do
    instance = described_class.allocate
    dlx = instance.queue_options.dig(:arguments, :'x-dead-letter-exchange')
    expect(dlx).to eq 'node.dlx'
  end
end
