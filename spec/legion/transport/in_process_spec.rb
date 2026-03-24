# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/in_process'

RSpec.describe Legion::Transport::InProcess do
  after { Legion::Transport::Local.reset! }

  describe 'exception classes' do
    it 'PreconditionFailed is a StandardError' do
      expect(described_class::PreconditionFailed.ancestors).to include(StandardError)
    end

    it 'ChannelAlreadyClosed is a StandardError' do
      expect(described_class::ChannelAlreadyClosed.ancestors).to include(StandardError)
    end

    it 'ChannelLevelException is a StandardError' do
      expect(described_class::ChannelLevelException.ancestors).to include(StandardError)
    end
  end

  describe 'DeliveryInfo' do
    it 'is a Struct with keyword_init' do
      di = described_class::DeliveryInfo.new(delivery_tag: 'tag1', routing_key: 'rk', exchange: 'ex')
      expect(di.delivery_tag).to eq('tag1')
      expect(di.routing_key).to eq('rk')
      expect(di.exchange).to eq('ex')
    end
  end

  describe 'MessageProperties' do
    it 'is a Struct with keyword_init' do
      mp = described_class::MessageProperties.new(
        content_type:     'application/json',
        headers:          {},
        timestamp:        Time.now,
        content_encoding: nil
      )
      expect(mp.content_type).to eq('application/json')
      expect(mp.headers).to eq({})
      expect(mp.content_encoding).to be_nil
    end
  end

  describe Legion::Transport::InProcess::Session do
    subject(:session) { described_class.new }

    it 'starts closed' do
      expect(session.open?).to be false
      expect(session.closed?).to be true
    end

    it 'opens after start' do
      session.start
      expect(session.open?).to be true
      expect(session.closed?).to be false
    end

    it 'start returns self' do
      expect(session.start).to be(session)
    end

    it 'closes after close' do
      session.start
      session.close
      expect(session.open?).to be false
      expect(session.closed?).to be true
    end

    it 'creates a channel' do
      channel = session.create_channel
      expect(channel).to be_a(Legion::Transport::InProcess::Channel)
    end

    it 'create_channel accepts id and pool_size' do
      channel = session.create_channel(1, 2)
      expect(channel).to be_a(Legion::Transport::InProcess::Channel)
    end

    it 'on_blocked is a no-op' do
      expect { session.on_blocked { nil } }.not_to raise_error
    end

    it 'on_unblocked is a no-op' do
      expect { session.on_unblocked { nil } }.not_to raise_error
    end

    it 'after_recovery_completed is a no-op' do
      expect { session.after_recovery_completed { nil } }.not_to raise_error
    end

    it 'close calls Local.reset!' do
      session.start
      Legion::Transport::Local.publish('ex', 'rk', 'data')
      session.close
      expect(Legion::Transport::Local.queue_depth('rk')).to eq(0)
    end
  end

  describe Legion::Transport::InProcess::Channel do
    subject(:channel) { described_class.new }

    it 'starts open' do
      expect(channel.open?).to be true
    end

    it 'closes after close' do
      channel.close
      expect(channel.open?).to be false
    end

    it 'prefetch returns count' do
      expect(channel.prefetch(5)).to eq(5)
    end

    it 'prefetch accepts global flag' do
      expect(channel.prefetch(3, _global: true)).to eq(3)
    end

    it 'basic_qos delegates to prefetch' do
      expect(channel.basic_qos(10)).to eq(10)
    end

    it 'exchange_declare is a no-op' do
      expect { channel.exchange_declare('ex', 'topic') }.not_to raise_error
    end

    it 'acknowledge is a no-op' do
      expect { channel.acknowledge('tag') }.not_to raise_error
    end

    it 'reject is a no-op' do
      expect { channel.reject('tag') }.not_to raise_error
    end

    it 'exchange_delete is a no-op' do
      expect { channel.exchange_delete('ex') }.not_to raise_error
    end
  end

  describe Legion::Transport::InProcess::Exchange do
    subject(:exchange) { described_class.new(channel, 'topic', 'my.exchange') }

    let(:channel) { Legion::Transport::InProcess::Channel.new }

    it 'stores name, type, channel' do
      expect(exchange.name).to eq('my.exchange')
      expect(exchange.type).to eq('topic')
      expect(exchange.channel).to be(channel)
    end

    it 'publish delegates to Local.publish' do
      received = nil
      Legion::Transport::Local.subscribe('my.key') { |msg| received = msg }
      exchange.publish('hello', routing_key: 'my.key')
      expect(received).to eq('hello')
    end

    it 'publish uses empty routing_key by default' do
      received = nil
      Legion::Transport::Local.subscribe('') { |msg| received = msg }
      exchange.publish('data')
      expect(received).to eq('data')
    end

    it 'delete returns true' do
      expect(exchange.delete).to be true
    end

    it 'delete accepts keyword args' do
      expect(exchange.delete(if_unused: true)).to be true
    end
  end

  describe Legion::Transport::InProcess::Queue do
    subject(:queue) { described_class.new(channel, 'my.queue') }

    let(:channel) { Legion::Transport::InProcess::Channel.new }

    it 'stores name and channel' do
      expect(queue.name).to eq('my.queue')
      expect(queue.channel).to be(channel)
    end

    it 'bind stores binding and returns self' do
      exchange = Legion::Transport::InProcess::Exchange.new(channel, 'topic', 'ex')
      result = queue.bind(exchange, routing_key: 'some.key')
      expect(result).to be(queue)
    end

    it 'subscribe returns a Consumer' do
      consumer = queue.subscribe { |_di, _meta, _payload| nil }
      expect(consumer).to be_a(Legion::Transport::InProcess::Consumer)
    end

    it 'subscribe creates a consumer with a generated tag' do
      consumer = queue.subscribe { |_di, _meta, _payload| nil }
      expect(consumer.consumer_tag).not_to be_nil
    end

    it 'subscribe uses provided consumer_tag' do
      consumer = queue.subscribe(consumer_tag: 'my-tag') { |_di, _meta, _payload| nil }
      expect(consumer.consumer_tag).to eq('my-tag')
    end

    it 'subscribe with binding routing_key receives messages' do
      exchange = Legion::Transport::InProcess::Exchange.new(channel, 'topic', 'ex')
      queue.bind(exchange, routing_key: 'task.work')

      received = []
      queue.subscribe do |delivery_info, metadata, payload|
        received << { di: delivery_info, meta: metadata, payload: payload }
      end

      Legion::Transport::Local.publish('ex', 'task.work', 'job1')
      expect(received.size).to eq(1)
      expect(received.first[:payload]).to eq('job1')
    end

    it 'subscribe delivery_info has correct fields' do
      exchange = Legion::Transport::InProcess::Exchange.new(channel, 'topic', 'my.exchange')
      queue.bind(exchange, routing_key: 'rk.test')

      delivery_infos = []
      queue.subscribe { |di, _meta, _payload| delivery_infos << di }

      Legion::Transport::Local.publish('my.exchange', 'rk.test', 'payload')
      expect(delivery_infos.first.routing_key).to eq('rk.test')
      expect(delivery_infos.first.exchange).to eq('my.queue')
      expect(delivery_infos.first.delivery_tag).not_to be_nil
    end

    it 'subscribe metadata has correct fields' do
      exchange = Legion::Transport::InProcess::Exchange.new(channel, 'topic', 'ex')
      queue.bind(exchange, routing_key: 'meta.test')

      metadatas = []
      queue.subscribe { |_di, meta, _payload| metadatas << meta }

      Legion::Transport::Local.publish('ex', 'meta.test', 'p')
      expect(metadatas.first.content_type).to eq('application/json')
      expect(metadatas.first.headers).to eq({})
    end

    it 'subscribe falls back to queue name when no bindings' do
      received = []
      queue.subscribe { |_di, _meta, payload| received << payload }

      Legion::Transport::Local.publish('ex', 'my.queue', 'msg')
      expect(received).to eq(['msg'])
    end

    it 'subscribe falls back to queue name when binding has empty routing_key' do
      exchange = Legion::Transport::InProcess::Exchange.new(channel, 'topic', 'ex')
      queue.bind(exchange, routing_key: '')

      received = []
      queue.subscribe { |_di, _meta, payload| received << payload }

      Legion::Transport::Local.publish('ex', 'my.queue', 'fallback')
      expect(received).to eq(['fallback'])
    end

    it 'acknowledge is a no-op' do
      expect { queue.acknowledge('tag') }.not_to raise_error
    end

    it 'reject is a no-op' do
      expect { queue.reject('tag') }.not_to raise_error
    end

    it 'delete returns true' do
      expect(queue.delete).to be true
    end
  end

  describe Legion::Transport::InProcess::Consumer do
    subject(:consumer) { described_class.new(nil, nil, 'tag-abc') }

    it 'stores consumer_tag' do
      expect(consumer.consumer_tag).to eq('tag-abc')
    end

    it 'starts not cancelled' do
      expect(consumer.cancelled?).to be false
    end

    it 'cancel sets cancelled' do
      consumer.cancel
      expect(consumer.cancelled?).to be true
    end
  end
end
