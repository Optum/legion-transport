# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/messages/dynamic'

RSpec.describe Legion::Transport::Messages::Dynamic do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Message' do
    expect(described_class.ancestors).to include(Legion::Transport::Message)
  end

  it 'is defined under Legion::Transport::Messages' do
    expect(described_class.name).to eq 'Legion::Transport::Messages::Dynamic'
  end

  it 'has an options accessor' do
    expect(described_class.instance_methods).to include(:options, :options=)
  end

  it 'returns task as the message type' do
    instance = described_class.allocate
    expect(instance.type).to eq 'task'
  end
end
