# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/messages/task_log'

RSpec.describe Legion::Transport::Messages::TaskLog do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Message' do
    expect(described_class.ancestors).to include(Legion::Transport::Message)
  end

  it 'is defined under Legion::Transport::Messages' do
    expect(described_class.name).to eq 'Legion::Transport::Messages::TaskLog'
  end

  it 'returns the Task exchange class' do
    instance = described_class.allocate
    expect(instance.exchange).to eq Legion::Transport::Exchanges::Task
  end

  it 'returns false for generate_task?' do
    instance = described_class.allocate
    expect(instance.generate_task?).to eq false
  end

  describe '#routing_key' do
    it 'includes the task_id in the routing key' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { task_id: 42 })
      expect(instance.routing_key).to eq 'task.logs.create.42'
    end
  end

  describe '#validate' do
    it 'coerces a String task_id to Integer' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { task_id: '7' })
      instance.validate
      expect(instance.instance_variable_get(:@options)[:task_id]).to eq 7
    end

    it 'raises RuntimeError when task_id is not an integer' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { task_id: nil })
      expect { instance.validate }.to raise_error(RuntimeError)
    end

    it 'sets @valid to true when task_id is a valid integer' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { task_id: 1 })
      instance.validate
      expect(instance.instance_variable_get(:@valid)).to eq true
    end
  end

  describe '#message' do
    it 'sets function to add_log and runner_class to tasker log runner' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { task_id: 5 })
      msg = instance.message
      expect(msg[:function]).to eq 'add_log'
      expect(msg[:runner_class]).to eq 'Legion::Extensions::Tasker::Runners::Log'
    end
  end
end
