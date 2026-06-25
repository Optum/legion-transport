# frozen_string_literal: true

require 'legion/logging/helper'
require_relative 'defaults'

module Legion
  module Transport
    module Kafka
      # Wraps an rdkafka producer with connection lifecycle management.
      # The underlying producer handle is lazily created on first use and
      # shared across calls (rdkafka producers are thread-safe).
      module Producer
        class << self
          include Legion::Logging::Helper

          # Publish a message to a Kafka topic.
          #
          # @param topic     [String]
          # @param payload   [String, Hash] Hash values are JSON-encoded
          # @param key       [String, nil]  partition key
          # @param headers   [Hash]         Kafka message headers
          # @param partition [Integer, nil] explicit partition; nil = librdkafka auto-assign
          # @return [Hash] { topic:, partition:, offset: }
          def publish(topic, payload, key: nil, headers: {}, partition: nil)
            encoded = encode(payload)
            delivery_handle = produce_message(topic, encoded, key:       key,
                                                              headers:   stringify_headers(headers),
                                                              partition: partition)
            report = delivery_handle.wait(max_wait_timeout: delivery_timeout)
            log_publish(topic, key, report)
            { topic: report.topic_name, partition: report.partition, offset: report.offset }
          rescue Legion::Transport::Kafka::PublishError => e
            handle_exception(e, level: :error, handled: false, operation: 'transport.kafka.producer.publish')
            raise
          rescue StandardError => e
            handle_exception(e, level: :error, handled: false, operation: 'transport.kafka.producer.publish',
                             topic: topic)
            raise Legion::Transport::Kafka::PublishError, "Kafka publish to #{topic} failed: #{e.message}"
          end

          # Close the underlying producer and flush any in-flight messages.
          def reset!
            @mutex&.synchronize do
              @producer&.close
              @producer = nil
            end
          end

          private

          def produce_message(topic, payload, key:, headers:, partition:)
            opts = { topic: topic, payload: payload }
            opts[:key]       = key       unless key.nil?
            opts[:headers]   = headers   unless headers.empty?
            opts[:partition] = partition unless partition.nil?
            handle(opts)
          rescue StandardError => e
            handle_exception(e, level: :warn, handled: false, operation: 'transport.kafka.producer.produce_message',
                             topic: topic)
            raise Legion::Transport::Kafka::PublishError, e.message
          end

          def handle(opts)
            producer.produce(**opts)
          end

          def producer
            mutex.synchronize do
              @producer ||= build_producer
            end
          end

          def mutex
            @mutex ||= Mutex.new
          end

          def build_producer
            config = producer_config
            ::Rdkafka::Config.new(config).producer
          end

          def producer_config
            settings   = Legion::Transport::Kafka.kafka_settings
            p_settings = settings[:producer] || DEFAULTS[:producer]
            brokers    = Array(settings[:brokers]).join(',')

            cfg = {
              'bootstrap.servers'  => brokers,
              'acks'               => (p_settings[:acks] || 'all').to_s,
              'retries'            => (p_settings[:retries] || 3).to_i,
              'retry.backoff.ms'   => (p_settings[:retry_backoff_ms] || 100).to_i,
              'message.timeout.ms' => (p_settings[:message_timeout_ms] || 30_000).to_i,
              'compression.codec'  => (p_settings[:compression] || 'none').to_s,
              'batch.size'         => (p_settings[:batch_size] || 100).to_i,
              'linger.ms'          => (p_settings[:linger_ms] || 5).to_i
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

          def delivery_timeout
            settings = Legion::Transport::Kafka.kafka_settings
            ((settings[:producer] || DEFAULTS[:producer])[:message_timeout_ms] || 30_000) / 1_000.0
          end

          def encode(payload)
            return payload if payload.is_a?(String)

            Legion::JSON.dump(payload)
          rescue StandardError => e
            handle_exception(e, level: :warn, handled: true, operation: 'transport.kafka.producer.encode')
            payload.to_s
          end

          def stringify_headers(headers)
            headers.transform_keys(&:to_s).transform_values(&:to_s)
          end

          def log_publish(topic, key, report)
            log.debug(
              "Kafka published topic=#{topic} partition=#{report.partition} " \
              "offset=#{report.offset}#{" key=#{key}" if key}"
            )
          end
        end
      end
    end
  end
end
