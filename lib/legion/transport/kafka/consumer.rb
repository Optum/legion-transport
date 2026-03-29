# frozen_string_literal: true

require_relative 'defaults'
require_relative 'incoming_message'

module Legion
  module Transport
    module Kafka
      # Consumer wraps rdkafka consumer handles for subscribe and replay operations.
      # Each subscribe/replay call creates its own isolated consumer handle so that
      # multiple topics and consumer groups can coexist in a single process.
      module Consumer
        class << self
          # Subscribe to one or more topics and yield each message to the block.
          # Runs synchronously in the calling thread — wrap in a Thread or actor
          # for background processing.
          #
          # @param topics         [String, Array<String>]
          # @param group          [String]
          # @param from_beginning [Boolean] true = earliest, false = latest
          # @param max_messages   [Integer, nil] stop after N messages; nil = run until stopped
          # @yield [IncomingMessage]
          def subscribe(topics, group:, from_beginning: false, max_messages: nil)
            topic_list = Array(topics)
            cfg        = consumer_config(group: group, from_beginning: from_beginning)
            consumer   = ::Rdkafka::Config.new(cfg).consumer

            begin
              consumer.subscribe(*topic_list)
              log_subscribe(topic_list, group)

              count = 0
              loop do
                message = consumer.poll(poll_timeout_ms)
                next if message.nil?

                yield IncomingMessage.new(message)

                count += 1
                commit_if_needed(consumer, count)
                break if max_messages && count >= max_messages
              end
            rescue StopIteration
              # clean exit from consumer loop
            ensure
              consumer.close
            end
          rescue StandardError => e
            raise Legion::Transport::Kafka::ConsumerError, "Kafka consumer error: #{e.message}"
          end

          # Replay a topic from a specific point without disturbing production offsets.
          # A temporary consumer group is used so that production group offsets are
          # unaffected. The consumer reads until caught up to the high-water mark at
          # the time replay started, then exits.
          #
          # @param topic          [String]
          # @param from_beginning [Boolean]
          # @param from_offset    [Integer, nil] explicit partition-0 start offset
          # @param from_timestamp [Time, nil] seek to nearest offset for this timestamp
          # @param replay_group   [String] isolated group ID for this replay session
          # @yield [IncomingMessage]
          def replay(topic, replay_group:, from_beginning: true, from_offset: nil, from_timestamp: nil)
            cfg      = consumer_config(group: replay_group, from_beginning: from_beginning)
            consumer = ::Rdkafka::Config.new(cfg).consumer

            begin
              consumer.subscribe(topic)

              # Seek if an explicit offset or timestamp was provided.
              if from_offset || from_timestamp
                seek_consumer(consumer, topic, from_offset:    from_offset,
                                               from_timestamp: from_timestamp)
              end

              log_replay(topic, replay_group, from_beginning: from_beginning,
                                              from_offset:    from_offset,
                                              from_timestamp: from_timestamp)

              loop do
                message = consumer.poll(poll_timeout_ms)
                break if message.nil?

                yield IncomingMessage.new(message)
              end
            ensure
              consumer.close
            end
          rescue StandardError => e
            raise Legion::Transport::Kafka::ConsumerError, "Kafka replay error on #{topic}: #{e.message}"
          end

          # No persistent state to reset; included for symmetry with Producer.reset!
          def reset!
            true
          end

          private

          def consumer_config(group:, from_beginning:)
            settings   = Legion::Transport::Kafka.kafka_settings
            c_settings = settings[:consumer] || DEFAULTS[:consumer]
            brokers    = Array(settings[:brokers]).join(',')

            auto_reset = from_beginning ? 'earliest' : (c_settings[:auto_offset_reset] || 'latest').to_s

            cfg = {
              'bootstrap.servers'    => brokers,
              'group.id'             => group.to_s,
              'auto.offset.reset'    => auto_reset,
              'enable.auto.commit'   => (c_settings[:enable_auto_commit] || false).to_s,
              'max.poll.interval.ms' => (c_settings[:max_poll_interval_ms] || 300_000).to_i,
              'session.timeout.ms'   => (c_settings[:session_timeout_ms] || 30_000).to_i
            }

            apply_security!(cfg, settings[:security] || DEFAULTS[:security])
            cfg
          end

          def apply_security!(cfg, sec)
            protocol = (sec[:protocol] || 'plaintext').to_s
            cfg['security.protocol'] = protocol
            return if protocol == 'plaintext'

            if sec[:sasl_mechanism].to_s != ''
              cfg['sasl.mechanism'] = sec[:sasl_mechanism].to_s
              cfg['sasl.username']  = sec[:sasl_username].to_s
              cfg['sasl.password']  = sec[:sasl_password].to_s
            end

            cfg['ssl.ca.location']          = sec[:ssl_ca_cert_path].to_s          if sec[:ssl_ca_cert_path].to_s != ''
            cfg['ssl.certificate.location'] = sec[:ssl_client_cert_path].to_s      if sec[:ssl_client_cert_path].to_s != ''
            cfg['ssl.key.location']         = sec[:ssl_client_cert_key_path].to_s  if sec[:ssl_client_cert_key_path].to_s != ''
          end

          def poll_timeout_ms
            settings = Legion::Transport::Kafka.kafka_settings
            ((settings[:consumer] || DEFAULTS[:consumer])[:poll_timeout_ms] || 1_000).to_i
          end

          def commit_interval
            settings = Legion::Transport::Kafka.kafka_settings
            ((settings[:consumer] || DEFAULTS[:consumer])[:commit_interval_messages] || 100).to_i
          end

          def commit_if_needed(consumer, count)
            consumer.commit if (count % commit_interval).zero?
          rescue StandardError => e
            return unless defined?(Legion::Logging)

            Legion::Logging.warn("Kafka consumer commit failed: #{e.message}")
          end

          def seek_consumer(consumer, topic, from_offset:, from_timestamp:)
            # Allow up to 5 polls to let the partition assignment settle.
            5.times { consumer.poll(200) }

            partition = ::Rdkafka::Consumer::TopicPartitionList.new
            partition.add_topic_and_partitions_with_offsets(topic,
                                                            0 => resolve_offset(consumer, topic, from_offset: from_offset, from_timestamp: from_timestamp))
            consumer.seek_to(partition)
          rescue StandardError => e
            return unless defined?(Legion::Logging)

            Legion::Logging.warn("Kafka consumer seek failed: #{e.message}")
          end

          def resolve_offset(consumer, topic, from_offset:, from_timestamp:)
            return from_offset if from_offset

            offsets_for_times = ::Rdkafka::Consumer::TopicPartitionList.new
            offsets_for_times.add_topic_and_partitions_with_offsets(
              topic, 0 => (from_timestamp.to_f * 1_000).to_i
            )
            result = consumer.offsets_for_times(offsets_for_times)
            result.to_h[topic]&.first&.last || 0
          rescue StandardError
            0
          end

          def log_subscribe(topics, group)
            return unless defined?(Legion::Logging)

            Legion::Logging.debug("Kafka subscribed topics=#{topics.join(',')} group=#{group}")
          end

          def log_replay(topic, group, from_beginning:, from_offset:, from_timestamp:)
            return unless defined?(Legion::Logging)

            desc = if from_offset
                     "offset=#{from_offset}"
                   elsif from_timestamp
                     "timestamp=#{from_timestamp}"
                   elsif from_beginning
                     'beginning'
                   else
                     'latest'
                   end
            Legion::Logging.info("Kafka replay topic=#{topic} from=#{desc} replay_group=#{group}")
          end
        end
      end
    end
  end
end
