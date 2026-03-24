# frozen_string_literal: true

require 'securerandom'
require_relative 'local'

module Legion
  module Transport
    module InProcess
      class PreconditionFailed < StandardError; end
      class ChannelAlreadyClosed < StandardError; end
      class ChannelLevelException < StandardError; end

      DeliveryInfo = Struct.new(:delivery_tag, :routing_key, :exchange)
      MessageProperties = Struct.new(:content_type, :headers, :timestamp, :content_encoding)

      class Session
        def initialize
          @open = false
        end

        def start
          @open = true
          Legion::Transport::Local.setup
          self
        end

        def open?
          @open
        end

        def closed?
          !@open
        end

        def close
          @open = false
          Legion::Transport::Local.reset!
        end

        def create_channel(_id = nil, _pool_size = 1, **)
          Channel.new
        end

        def on_blocked(&); end

        def on_unblocked(&); end

        def after_recovery_completed(&); end
      end

      class Channel
        def initialize
          @open = true
        end

        def open?
          @open
        end

        def close
          @open = false
        end

        def prefetch(count, _global: false)
          count
        end

        def basic_qos(count, _global: false)
          prefetch(count)
        end

        def exchange_declare(*); end

        def acknowledge(*); end

        def reject(*); end

        def exchange_delete(*); end
      end

      class Exchange
        attr_reader :name, :type, :channel

        def initialize(channel, type, name, _opts = {})
          @channel = channel
          @type = type
          @name = name
        end

        def publish(payload, routing_key: '', **)
          Legion::Transport::Local.publish(@name, routing_key, payload)
        end

        def delete(**)
          true
        end
      end

      class Queue
        attr_reader :name, :channel

        def initialize(channel, name, _opts = {})
          @channel = channel
          @name = name
          @bindings = []
        end

        def bind(exchange, routing_key: '#', **)
          @bindings << { exchange: exchange, routing_key: routing_key }
          self
        end

        def subscribe(manual_ack: true, _block: false, consumer_tag: nil, _on_cancellation: nil, **, &callback)
          tag = consumer_tag || SecureRandom.uuid
          consumer = Consumer.new(@channel, self, tag, !manual_ack, false)

          keys = @bindings.map { |b| b[:routing_key] }.reject { |k| k.nil? || k.empty? }
          keys = [@name] if keys.empty?

          keys.each do |rk|
            Legion::Transport::Local.subscribe(rk) do |payload|
              delivery_info = DeliveryInfo.new(
                delivery_tag: SecureRandom.uuid,
                routing_key:  rk,
                exchange:     @name
              )
              metadata = MessageProperties.new(
                content_type:     'application/json',
                headers:          {},
                timestamp:        ::Time.now,
                content_encoding: nil
              )
              callback.call(delivery_info, metadata, payload)
            end
          end

          consumer
        end

        def acknowledge(*); end

        def reject(*); end

        def delete
          true
        end
      end

      class Consumer
        attr_reader :consumer_tag

        def initialize(_channel, _queue, consumer_tag, *_rest)
          @consumer_tag = consumer_tag
          @cancelled = false
        end

        def cancel
          @cancelled = true
        end

        def cancelled?
          @cancelled
        end
      end
    end
  end
end
