# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/messages/request_cluster_secret'

RSpec.describe Legion::Transport::Messages::RequestClusterSecret do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Message' do
    expect(described_class.ancestors).to include(Legion::Transport::Message)
  end

  it 'is defined under Legion::Transport::Messages' do
    expect(described_class.name).to eq 'Legion::Transport::Messages::RequestClusterSecret'
  end

  it 'returns the correct routing key' do
    instance = described_class.allocate
    expect(instance.routing_key).to eq 'node.crypt.push_cluster_secret'
  end

  it 'returns the Node exchange class' do
    instance = described_class.allocate
    expect(instance.exchange).to eq Legion::Transport::Exchanges::Node
  end

  it 'returns false for encrypt?' do
    instance = described_class.allocate
    expect(instance.encrypt?).to eq false
  end

  it 'returns task as the message type' do
    instance = described_class.allocate
    expect(instance.type).to eq 'task'
  end

  it 'sets @valid to true on validate' do
    instance = described_class.allocate
    instance.validate
    expect(instance.instance_variable_get(:@valid)).to eq true
  end
end
