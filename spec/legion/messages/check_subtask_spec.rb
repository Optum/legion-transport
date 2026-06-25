# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/messages/check_subtask'

RSpec.describe Legion::Transport::Messages::CheckSubtask do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Message' do
    expect(described_class.ancestors).to include(Legion::Transport::Message)
  end

  it 'is defined under Legion::Transport::Messages' do
    expect(described_class.name).to eq 'Legion::Transport::Messages::CheckSubtask'
  end

  it 'returns the correct routing key' do
    instance = described_class.allocate
    expect(instance.routing_key).to eq 'task.subtask.check'
  end

  it 'returns the correct exchange class' do
    instance = described_class.allocate
    expect(instance.exchange).to eq Legion::Transport::Exchanges::Task
  end

  it 'returns the correct exchange name string' do
    instance = described_class.allocate
    expect(instance.exchange_name).to eq 'Legion::Transport::Exchanges::Task'
  end

  it 'sets @valid to true on validate' do
    instance = described_class.allocate
    instance.validate
    expect(instance.instance_variable_get(:@valid)).to eq true
  end
end
