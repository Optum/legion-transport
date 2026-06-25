# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/local'

RSpec.describe Legion::Transport::Local do
  before { described_class.reset! }

  describe '.publish and .subscribe' do
    it 'delivers message to subscriber' do
      received = nil
      described_class.subscribe('test.queue') { |msg| received = msg }
      described_class.publish('test.exchange', 'test.queue', { data: 'hello' })
      expect(received).to eq({ data: 'hello' })
    end

    it 'queues messages before subscriber connects' do
      described_class.publish('ex', 'q1', 'msg1')
      described_class.publish('ex', 'q1', 'msg2')

      received = []
      described_class.subscribe('q1') { |msg| received << msg }
      expect(received).to eq(%w[msg1 msg2])
    end

    it 'tracks queue depth' do
      described_class.publish('ex', 'depth_test', 'a')
      described_class.publish('ex', 'depth_test', 'b')
      expect(described_class.queue_depth('depth_test')).to eq(2)
    end

    it 'returns publish result hash' do
      result = described_class.publish('ex', 'rk', 'data')
      expect(result).to eq({ published: true, routing_key: 'rk' })
    end
  end

  describe '.reset!' do
    it 'clears all queues and subscribers' do
      described_class.publish('ex', 'q', 'data')
      described_class.reset!
      expect(described_class.queue_depth('q')).to eq(0)
    end
  end

  describe '.active?' do
    it 'returns true' do
      expect(described_class.active?).to be true
    end
  end
end
