# frozen_string_literal: true

require 'legion/logging/helper'

module Legion
  module Transport
    class Consumer < Legion::Transport::CONNECTOR::Consumer
      include Legion::Transport::Common

      attr_reader :consumer_tag

      def initialize(queue:, no_ack: false, exclusive: false, consumer_tag: generate_consumer_tag, **opts)
        @consumer_tag = consumer_tag
        super(channel, queue, consumer_tag, no_ack, exclusive, opts)
        queue_name = queue.respond_to?(:name) ? queue.name : queue.to_s
        log.info "Consumer subscribed to #{queue_name} with tag #{consumer_tag}"
      end
    end
  end
end
