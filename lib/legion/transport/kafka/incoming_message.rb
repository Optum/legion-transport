# frozen_string_literal: true

module Legion
  module Transport
    module Kafka
      # Wraps an rdkafka message with a clean, framework-consistent interface.
      # Passed to subscriber blocks instead of the raw Rdkafka::Consumer::Message.
      class IncomingMessage
        attr_reader :topic, :partition, :offset, :key, :headers, :timestamp, :raw

        def initialize(rdkafka_message)
          @raw       = rdkafka_message
          @topic     = rdkafka_message.topic
          @partition = rdkafka_message.partition
          @offset    = rdkafka_message.offset
          @key       = rdkafka_message.key
          @headers   = rdkafka_message.headers || {}
          @timestamp = rdkafka_message.timestamp
          @payload   = rdkafka_message.payload
        end

        # Returns the raw string payload.
        attr_reader :payload

        # Attempts to parse the payload as JSON; returns the raw string on failure.
        def decoded_payload
          return @payload unless @payload.is_a?(String)

          Legion::JSON.parse(@payload)
        rescue StandardError
          @payload
        end

        def to_s
          "#{topic}[#{partition}]@#{offset}"
        end

        def inspect
          "#<#{self.class} topic=#{topic} partition=#{partition} offset=#{offset}>"
        end
      end
    end
  end
end
