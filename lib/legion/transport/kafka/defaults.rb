# frozen_string_literal: true

module Legion
  module Transport
    module Kafka
      DEFAULTS = {
        enabled:        false,
        brokers:        [ENV.fetch('transport.kafka.brokers', '127.0.0.1:9092')],
        consumer_group: ENV.fetch('transport.kafka.consumer_group', 'legion'),
        producer:       {
          acks:               ENV.fetch('transport.kafka.producer.acks', 'all'),
          retries:            (ENV['transport.kafka.producer.retries'] || 3).to_i,
          retry_backoff_ms:   (ENV['transport.kafka.producer.retry_backoff_ms'] || 100).to_i,
          message_timeout_ms: (ENV['transport.kafka.producer.message_timeout_ms'] || 30_000).to_i,
          compression:        ENV.fetch('transport.kafka.producer.compression', 'none'),
          batch_size:         (ENV['transport.kafka.producer.batch_size'] || 100).to_i,
          linger_ms:          (ENV['transport.kafka.producer.linger_ms'] || 5).to_i
        },
        consumer:       {
          poll_timeout_ms:          (ENV['transport.kafka.consumer.poll_timeout_ms'] || 1_000).to_i,
          max_poll_interval_ms:     (ENV['transport.kafka.consumer.max_poll_interval_ms'] || 300_000).to_i,
          session_timeout_ms:       (ENV['transport.kafka.consumer.session_timeout_ms'] || 30_000).to_i,
          auto_offset_reset:        ENV.fetch('transport.kafka.consumer.auto_offset_reset', 'latest'),
          enable_auto_commit:       ENV.fetch('transport.kafka.consumer.enable_auto_commit', 'false') == 'true',
          commit_interval_messages: (ENV['transport.kafka.consumer.commit_interval_messages'] || 100).to_i
        },
        admin:          {
          operation_timeout_ms: (ENV['transport.kafka.admin.operation_timeout_ms'] || 10_000).to_i
        },
        security:       {
          protocol:                 ENV.fetch('transport.kafka.security.protocol', 'plaintext'),
          sasl_mechanism:           ENV.fetch('transport.kafka.security.sasl_mechanism', ''),
          sasl_username:            ENV.fetch('transport.kafka.security.sasl_username', ''),
          sasl_password:            ENV.fetch('transport.kafka.security.sasl_password', ''),
          ssl_ca_cert_path:         ENV.fetch('transport.kafka.security.ssl_ca_cert_path', ''),
          ssl_client_cert_path:     ENV.fetch('transport.kafka.security.ssl_client_cert_path', ''),
          ssl_client_cert_key_path: ENV.fetch('transport.kafka.security.ssl_client_cert_key_path', '')
        }
      }.freeze
    end
  end
end
