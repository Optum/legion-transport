# frozen_string_literal: true

module Legion
  module Transport
    class Exchange < Legion::Transport::CONNECTOR::Exchange
      include Legion::Transport::Common

      # Thread-local cache of declared exchange instances keyed by class name.
      # Avoids redundant exchange_declare calls on every publish.
      @instance_cache = Concurrent::ThreadLocalVar.new { {} }

      class << self
        def instance_cache
          Legion::Transport::Exchange.instance_variable_get(:@instance_cache)
        end

        def cached_instance
          cache = instance_cache.value
          inst = cache[name]
          return inst if inst&.channel&.open?

          cache.delete(name)
          nil
        end

        def cache_instance(inst)
          instance_cache.value[name] = inst
        end

        def clear_cache
          instance_cache.value.clear
        end
      end

      def initialize(exchange = exchange_name, options = {})
        @options = options
        @explicit_channel = @options.delete(:channel)
        @type = options[:type] || default_type
        super(channel, @type, exchange, options_builder(default_options, exchange_options, @options))
        self.class.cache_instance(self) if self.class.respond_to?(:cache_instance)
      rescue Legion::Transport::CONNECTOR::PreconditionFailed, Legion::Transport::CONNECTOR::ChannelAlreadyClosed
        raise unless @retries.nil?

        @retries = 1
        @channel&.close rescue nil # rubocop:disable Style/RescueModifier
        delete_exchange(exchange)
        retry
      end

      def delete_exchange(exchange)
        Legion::Transport.logger.warn "Exchange:#{exchange} exists with wrong parameters, deleting and creating"
        @channel = Legion::Transport::Connection.channel
        @channel.exchange_delete(exchange)
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
        derive_segments.join('.')
      end

      def exchange_options
        Concurrent::Hash.new
      end

      def delete(options = {})
        super
        true
      rescue Legion::Transport::CONNECTOR::PreconditionFailed => e
        Legion::Logging.warn("Exchange#delete precondition failed: #{e.message}") if defined?(Legion::Logging)
        false
      end

      def default_type
        'topic'
      end

      def channel
        @channel ||= @explicit_channel || Legion::Transport::Connection.channel
      rescue Legion::Transport::CONNECTOR::ChannelLevelException => e
        # Prefer closing the channel from the exception (available even when @channel is nil
        # because the exception was raised before assignment completed).
        error_channel = e.respond_to?(:channel) ? e.channel : @channel
        error_channel&.close rescue nil # rubocop:disable Style/RescueModifier
        @channel = Legion::Transport::Connection.channel
        raise e unless @channel.open?

        @channel
      end
    end
  end
end
