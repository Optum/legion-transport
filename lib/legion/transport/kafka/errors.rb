# frozen_string_literal: true

module Legion
  module Transport
    module Kafka
      # Raised when the Kafka adapter is accessed but disabled in settings.
      class DisabledError < StandardError; end

      # Raised when the rdkafka gem is not available.
      class UnavailableError < StandardError; end

      # Raised when a publish operation fails after retries.
      class PublishError < StandardError; end

      # Raised when a consumer encounters an unrecoverable error.
      class ConsumerError < StandardError; end

      # Raised when an admin operation fails.
      class AdminError < StandardError; end
    end
  end
end
