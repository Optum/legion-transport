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
      rescue Legion::Transport::CONNECTOR::PreconditionFailed, Legion::Transport::CONNECTOR::ChannelAlreadyClosed => e
        handle_exception(e, level: :warn, handled: true, operation: 'transport.exchange.initialize', exchange: exchange)
        raise unless @retries.nil?
        raise if credential_scoping_enabled? && (bootstrap_phase? || (!topology_mode? && Legion::Identity::Process.resolved?))

        @retries = 1
        # Only close the channel if it was not explicitly provided by the caller.
        safely_close_channel(@channel) if @explicit_channel.nil? || @channel != @explicit_channel
        delete_exchange(exchange)
        retry
      end

      def delete_exchange(exchange)
        log.warn "Exchange:#{exchange} exists with wrong parameters, deleting and creating"
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
        return false unless credential_scoping_enabled?
        return false unless defined?(Legion::Identity::Process)
        return true  if bootstrap_phase?
        return false if topology_mode?

        true
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
        handle_exception(e, level: :warn, handled: true, operation: 'transport.exchange.delete')
        false
      end

      def default_type
        'topic'
      end

      def channel
        @channel ||= @explicit_channel || Legion::Transport::Connection.channel
      rescue Legion::Transport::CONNECTOR::ChannelLevelException => e
        handle_exception(e, level: :warn, handled: true, operation: 'transport.exchange.channel')
        # Prefer closing the channel from the exception (available even when @channel is nil
        # because the exception was raised before assignment completed).
        error_channel = e.respond_to?(:channel) ? e.channel : @channel
        safely_close_channel(error_channel)
        @channel = Legion::Transport::Connection.channel
        raise e unless @channel.open?

        @channel
      end

      private

      def credential_scoping_enabled?
        return false unless defined?(Legion::Settings)

        Legion::Settings.dig(:crypt, :vault, :dynamic_rmq_creds) == true
      end

      def bootstrap_phase?
        return false unless defined?(Legion::Identity::Process)

        !Legion::Identity::Process.resolved? && credential_scoping_enabled?
      end

      def topology_mode?
        return true unless defined?(Legion::Mode)

        Legion::Mode.infra? || Legion::Mode.worker?
      end

      def safely_close_channel(error_channel)
        error_channel&.close if error_channel&.open?
      rescue StandardError => e
        handle_exception(e, level: :warn, handled: true, operation: 'transport.exchange.close_channel')
      end
    end
  end
end
