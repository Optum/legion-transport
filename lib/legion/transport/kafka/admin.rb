# frozen_string_literal: true

require_relative 'defaults'

module Legion
  module Transport
    module Kafka
      # Thin wrapper around rdkafka admin operations.
      # Used internally to ensure topics exist before publishing/subscribing.
      module Admin
        class << self
          # Idempotently create a topic. Returns true if the topic was created or
          # already exists, raises AdminError on other failures.
          #
          # @param topic              [String]
          # @param partitions         [Integer]
          # @param replication_factor [Integer]
          # @param config             [Hash] topic-level config (e.g. +'retention.ms'+ => '604800000')
          # @return [Boolean]
          def ensure_topic(topic, partitions: 1, replication_factor: 1, config: {})
            admin  = build_admin
            handle = admin.create_topic(topic, partitions, replication_factor, config)
            handle.wait(max_wait_timeout: operation_timeout)
            log_created(topic, partitions)
            true
          rescue ::Rdkafka::RdkafkaError => e
            # Error code 36 = TOPIC_ALREADY_EXISTS — not a real error for our purposes.
            return true if e.respond_to?(:code) && e.code == :topic_already_exists
            return true if e.message.to_s.include?('TOPIC_ALREADY_EXISTS') || e.message.to_s.include?('Topic already exists')

            raise Legion::Transport::Kafka::AdminError, "ensure_topic(#{topic}) failed: #{e.message}"
          rescue StandardError => e
            raise Legion::Transport::Kafka::AdminError, "ensure_topic(#{topic}) failed: #{e.message}"
          ensure
            admin&.close rescue nil # rubocop:disable Style/RescueModifier
          end

          private

          def build_admin
            brokers = Array(Legion::Transport::Kafka.kafka_settings[:brokers]).join(',')
            cfg     = {
              'bootstrap.servers'  => brokers,
              'request.timeout.ms' => operation_timeout_ms
            }
            security = Legion::Transport::Kafka.kafka_settings[:security] || DEFAULTS[:security]
            apply_security!(cfg, security)
            ::Rdkafka::Config.new(cfg).admin
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

          def operation_timeout
            operation_timeout_ms / 1_000.0
          end

          def operation_timeout_ms
            settings = Legion::Transport::Kafka.kafka_settings
            ((settings[:admin] || DEFAULTS[:admin])[:operation_timeout_ms] || 10_000).to_i
          end

          def log_created(topic, partitions)
            return unless defined?(Legion::Logging)

            Legion::Logging.info("Kafka topic created topic=#{topic} partitions=#{partitions}")
          end
        end
      end
    end
  end
end
