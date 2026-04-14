# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/messages/subtask'

RSpec.describe Legion::Transport::Messages::SubTask do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Message' do
    expect(described_class.ancestors).to include(Legion::Transport::Message)
  end

  it 'is defined under Legion::Transport::Messages' do
    expect(described_class.name).to eq 'Legion::Transport::Messages::SubTask'
  end

  it 'returns the Task exchange class' do
    instance = described_class.allocate
    expect(instance.exchange).to eq Legion::Transport::Exchanges::Task
  end

  describe '#routing_key' do
    it 'returns conditioner routing key when conditions string is present' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { conditions: '{"foo":"bar"}' })
      expect(instance.routing_key).to eq 'task.subtask.conditioner'
    end

    it 'returns transform routing key when transformation string is present' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { conditions: '{}', transformation: '{"key":"val"}' })
      expect(instance.routing_key).to eq 'task.subtask.transform'
    end

    it 'returns nil when no routing conditions match' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { conditions: '{}', transformation: '{}' })
      expect(instance.routing_key).to be_nil
    end
  end

  describe '#message' do
    it 'returns a hash with transformation, conditions, and results when provided' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, {
                                       transformation: '{"key":"val"}',
                                       conditions:     '{"cond":"test"}',
                                       results:        { data: 'value' }
                                     })
      msg = instance.message
      expect(msg).to have_key(:transformation)
      expect(msg).to have_key(:conditions)
      expect(msg).to have_key(:results)
    end

    it 'omits keys with nil values' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, {})
      msg = instance.message
      expect(msg).not_to have_key(:transformation)
      expect(msg).not_to have_key(:conditions)
      expect(msg).not_to have_key(:results)
    end
  end

  describe '#validate' do
    it 'raises TypeError when function is not a String' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { function: 123 })
      expect { instance.validate }.to raise_error(TypeError)
    end

    it 'sets @valid to true when function is a String' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { function: 'my_function' })
      instance.validate
      expect(instance.instance_variable_get(:@valid)).to eq true
    end
  end
end
