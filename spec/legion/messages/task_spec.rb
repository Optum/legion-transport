# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/messages/task'

RSpec.describe Legion::Transport::Messages::Task do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Message' do
    expect(described_class.ancestors).to include(Legion::Transport::Message)
  end

  it 'is defined under Legion::Transport::Messages' do
    expect(described_class.name).to eq 'Legion::Transport::Messages::Task'
  end

  describe '#message' do
    it 'returns the full options hash' do
      instance = described_class.allocate
      opts = { function: 'do_thing', queue: 'myqueue' }
      instance.instance_variable_set(:@options, opts)
      expect(instance.message).to eq opts
    end
  end

  describe '#routing_key' do
    it 'returns the explicit routing_key option when present' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { routing_key: 'custom.key', function: 'fn' })
      expect(instance.routing_key).to eq 'custom.key'
    end

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

    it 'returns queue.function routing key when both are present' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { queue: 'myqueue', function: 'myfunc' })
      expect(instance.routing_key).to eq 'myqueue.myfunc'
    end
  end

  describe '#exchange' do
    let(:instance) do
      obj = described_class.allocate
      obj.instance_variable_set(:@options, options)
      obj
    end

    context 'when exchange option is a String' do
      let(:options) { { exchange: 'lex', function: 'task' } }

      it 'does not raise NoMethodError' do
        allow(Legion::Transport::Exchange).to receive(:new).with('lex').and_return(double('exchange'))
        expect { instance.exchange }.not_to raise_error
      end

      it 'instantiates the base Exchange class with the given string name' do
        exchange_double = double('exchange')
        expect(Legion::Transport::Exchange).to receive(:new).with('lex').and_return(exchange_double)
        expect(instance.exchange).to eq exchange_double
      end
    end

    context 'when exchange option is not set' do
      let(:options) { { function: 'task' } }

      it 'returns a Task exchange instance' do
        task_exchange = double('task_exchange')
        allow(Legion::Transport::Exchanges::Task).to receive(:new).and_return(task_exchange)
        expect(instance.exchange).to eq task_exchange
      end
    end
  end

  describe '#validate' do
    it 'raises TypeError when function is not a String' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { function: 42 })
      expect { instance.validate }.to raise_error(TypeError)
    end

    it 'sets @valid to true when function is a String' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, { function: 'my_task' })
      instance.validate
      expect(instance.instance_variable_get(:@valid)).to eq true
    end
  end
end
