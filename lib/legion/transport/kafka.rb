# frozen_string_literal: true

require 'securerandom'
require_relative 'kafka/errors'
require_relative 'kafka/producer'
require_relative 'kafka/consumer'
require_relative 'kafka/admin'

module Legion
  module Transport
    # Optional Kafka adapter for event streaming alongside RabbitMQ.
    #
    # Kafka is NOT a replacement for RabbitMQ task dispatch — it runs alongside
    # for patterns that need durable, replayable, append-only event logs:
    #   - Telemetry / metrics pipelines
    #   - Audit event streams
    #   - Change data capture / event sourcing
    #   - Consumer group fan-out with independent offset tracking
    #
    # Feature-flagged via +transport.kafka.enabled: false+ (default off).
    # Requires the +rdkafka+ gem as an optional runtime dependency.
    #
    # Usage:
    #   Legion::Transport::Kafka.publish('legion.audit', { event: 'login' })
    #   Legion::Transport::Kafka.subscribe('legion.telemetry', group: 'metrics') do |msg|
    #     process(msg)
    #   end
    #   Legion::Transport::Kafka.replay('legion.audit', from_beginning: true) do |msg|
    #     reprocess(msg)
    #   end
    module Kafka
      class << self
        # Returns true when the Kafka adapter is enabled and rdkafka is available.
        def enabled?
          return false unless kafka_settings[:enabled]

          require_rdkafka
          true
        rescue Legion::Transport::Kafka::UnavailableError
          false
        end

        # Publish a single message to a Kafka topic.
        #
        # @param topic [String] Kafka topic name
        # @param payload [String, Hash] message body; Hash is JSON-encoded automatically
        # @param key [String, nil] optional partition key
        # @param headers [Hash] optional message headers
        # @param partition [Integer, nil] explicit partition (nil = auto-assigned)
        # @return [Hash] delivery report { topic:, partition:, offset: }
        def publish(topic, payload, key: nil, headers: {}, partition: nil)
          require_enabled!
          Producer.publish(topic, payload, key: key, headers: headers, partition: partition)
        end

        # Subscribe to a Kafka topic with consumer group semantics.
        # Runs the block synchronously in the calling thread for each message.
        # For background polling, wrap in a Thread / actor.
        #
        # @param topic [String, Array<String>] topic(s) to subscribe to
        # @param group [String] consumer group ID (default from settings)
        # @param from_beginning [Boolean] start from earliest offset (default false = latest)
        # @param max_messages [Integer, nil] stop after N messages (nil = run forever)
        # @yield [message] called for each received message
        # @yieldparam message [Legion::Transport::Kafka::IncomingMessage]
        def subscribe(topic, group: default_group, from_beginning: false, max_messages: nil, &)
          require_enabled!
          Consumer.subscribe(topic, group: group, from_beginning: from_beginning,
                                    max_messages: max_messages, &)
        end

        # Replay a topic from a specific point.
        # Creates an isolated consumer group for the replay session so that production
        # offsets are not disturbed.
        #
        # @param topic [String] topic to replay
        # @param from_beginning [Boolean] start from offset 0 (default true for replay)
        # @param from_offset [Integer, nil] explicit partition-0 offset to start from
        # @param from_timestamp [Time, nil] seek to offset nearest this timestamp
        # @param replay_group [String] temporary consumer group ID
        # @yield [message] called for each replayed message
        def replay(topic, from_beginning: true, from_offset: nil, from_timestamp: nil,
                   replay_group: "legion-replay-#{SecureRandom.hex(4)}", &)
          require_enabled!
          Consumer.replay(topic,
                          from_beginning: from_beginning,
                          from_offset:    from_offset,
                          from_timestamp: from_timestamp,
                          replay_group:   replay_group,
                          &)
        end

        # Create a Kafka topic via the admin client.
        # Idempotent — returns true if the topic already exists.
        #
        # @param topic [String]
        # @param partitions [Integer]
        # @param replication_factor [Integer]
        # @param config [Hash] topic-level Kafka configs (e.g. retention.ms)
        def ensure_topic(topic, partitions: 1, replication_factor: 1, config: {})
          require_enabled!
          Admin.ensure_topic(topic, partitions:         partitions,
                                    replication_factor: replication_factor,
                                    config:             config)
        end

        # Returns the Kafka brokers list from settings.
        def brokers
          Array(kafka_settings[:brokers]).flatten.compact
        end

        # Returns the default consumer group from settings.
        def default_group
          kafka_settings[:consumer_group] || 'legion'
        end

        # Returns the raw Kafka settings hash.
        def kafka_settings
          Legion::Settings[:transport][:kafka]
        rescue StandardError
          Legion::Transport::Kafka::DEFAULTS
        end

        # Resets internal producer/consumer state (useful in tests).
        def reset!
          Producer.reset!
          Consumer.reset!
        end

        private

        def require_enabled!
          raise Legion::Transport::Kafka::DisabledError, 'Kafka adapter is not enabled (transport.kafka.enabled: false)' unless kafka_settings[:enabled]

          require_rdkafka
        end

        def require_rdkafka
          require 'rdkafka'
        rescue LoadError
          raise Legion::Transport::Kafka::UnavailableError,
                'rdkafka gem is required for Kafka support — add gem "rdkafka" to your Gemfile'
        end
      end
    end
  end
end
