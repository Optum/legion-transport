module Legion
  module Transport
    class Consumer < Legion::Transport::CONNECTOR::Consumer
      include Legion::Transport::Common
      attr_reader :consumer_tag

      def initialize(queue:, no_ack: false, exclusive: false, consumer_tag: generate_consumer_tag, **opts)
        @consumer_tag = consumer_tag
        super(channel, queue, consumer_tag, no_ack, exclusive, opts)
      end
    end
  end
end
