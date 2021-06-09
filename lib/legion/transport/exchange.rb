module Legion
  module Transport
    class Exchange < Legion::Transport::CONNECTOR::Exchange
      include Legion::Transport::Common

      def initialize(exchange = exchange_name, options = {})
        @options = options
        @type = options[:type] || default_type
        if Legion::Transport::TYPE == 'march_hare'
          super_options = options_builder(default_options, exchange_options, @options)
          super_options[:type] = @type
          super(channel, exchange, **super_options)
        else
          super(channel, @type, exchange, options_builder(default_options, exchange_options, @options))
        end
      rescue Legion::Transport::CONNECTOR::PreconditionFailed, Legion::Transport::CONNECTOR::ChannelAlreadyClosed
        raise unless @retries.nil?

        @retries = 1
        delete_exchange(exchange)
        retry
      end

      def delete_exchange(exchange)
        Legion::Transport.logger.warn "Exchange:#{exchange} exists with wrong parameters, deleting and creating"
        channel.exchange_delete(exchange)
      end

      def default_options
        hash = Concurrent::Hash.new
        hash[:durable] = true
        hash[:auto_delete] = false
        hash[:arguments] = {}
        hash[:passive] = passive?
        hash
      end

      def passive?
        false
      end

      def exchange_name
        self.class.ancestors.first.to_s.split('::')[2].downcase
      end

      def exchange_options
        Concurrent::Hash.new
      end

      def delete(options = {})
        super(options)
        true
      rescue Legion::Transport::CONNECTOR::PreconditionFailed
        false
      end

      def default_type
        'topic'
      end

      def channel
        @channel ||= Legion::Transport::Connection.channel
      rescue ChannelLevelException => e
        @channel = Legion::Transport::Connection.channel
        raise e unless @channel.open?
      end
    end
  end
end
