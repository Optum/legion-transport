# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/messages/task_update'

RSpec.describe Legion::Transport::Messages::TaskUpdate do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Message' do
    expect(described_class.ancestors).to include(Legion::Transport::Message)
  end

  it 'is defined under Legion::Transport::Messages' do
    expect(described_class.name).to eq 'Legion::Transport::Messages::TaskUpdate'
  end

  it 'returns the correct routing key' do
    instance = described_class.allocate
    expect(instance.routing_key).to eq 'task.update'
  end

  it 'returns the Task exchange class' do
    instance = described_class.allocate
    expect(instance.exchange).to eq Legion::Transport::Exchanges::Task
  end

  describe '#valid_status' do
    let(:instance) { described_class.allocate }

    it 'returns an Array' do
      expect(instance.valid_status).to be_an Array
    end

    it 'includes conditioner statuses' do
      expect(instance.valid_status).to include('conditioner.queued', 'conditioner.failed', 'conditioner.exception')
    end

    it 'includes transformer statuses' do
      expect(instance.valid_status).to include('transformer.queued', 'transformer.succeeded', 'transformer.exception')
    end

    it 'includes task statuses' do
      expect(instance.valid_status).to include(
        'task.scheduled', 'task.queued', 'task.completed', 'task.exception', 'task.delayed'
      )
    end

    it 'contains 11 total valid statuses' do
      expect(instance.valid_status.length).to eq 11
    end
  end
end
