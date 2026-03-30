# frozen_string_literal: true

module Legion
  module Transport
    module Helper
      # --- TTL Resolution ---
      # Override in your LEX to set a custom default message TTL for the extension.
      # Resolution chain: per-call :ttl option -> LEX override -> Settings -> nil (no expiration)
      def transport_default_ttl
        return nil unless defined?(Legion::Settings)

        Legion::Settings.dig(:transport, :messages, :ttl)
      rescue StandardError
        nil
      end

      # --- Namespace / Wiring ---

      def transport_path
        @transport_path ||= "#{full_path}/transport"
      end

      def transport_class
        @transport_class ||= lex_class::Transport
      end

      def messages
        @messages ||= transport_class::Messages
      end

      def queues
        @queues ||= transport_class::Queues
      end

      def exchanges
        @exchanges ||= transport_class::Exchanges
      end

      def default_exchange
        @default_exchange ||= build_default_exchange
      end

      def build_default_exchange
        return transport_class::Exchanges.const_get(lex_const, false) if transport_class::Exchanges.const_defined?(lex_const, false)

        amqp = amqp_prefix
        transport_class::Exchanges.const_set(lex_const, Class.new(Legion::Transport::Exchange) do
          define_method(:exchange_name) { amqp }
        end)
        @default_exchange = transport_class::Exchanges.const_get(lex_const, false)
      end

      # --- Status ---

      def transport_connected?
        return false unless defined?(Legion::Settings)

        !!Legion::Settings.dig(:transport, :connected)
      rescue StandardError
        false
      end

      def transport_session_open?
        Legion::Transport::Connection.session_open?
      rescue StandardError
        false
      end

      def transport_channel_open?
        Legion::Transport::Connection.channel_open?
      rescue StandardError
        false
      end

      def transport_lite_mode?
        Legion::Transport::Connection.lite_mode?
      end

      # --- Resource Info ---

      def transport_channel
        Legion::Transport::Connection.channel
      end

      def transport_spool_count
        Legion::Transport::Spool.count
      rescue StandardError
        0
      end

      # --- Publish Convenience ---

      def transport_publish(routing_key:, payload: {}, **opts)
        return false unless transport_connected?

        if opts.key?(:ttl)
          ttl = opts.delete(:ttl)
          opts[:expiration] = ttl.to_s if ttl
        elsif !opts.key?(:expiration)
          ttl = transport_default_ttl
          opts[:expiration] = ttl.to_s if ttl
        end
        encoded = payload.is_a?(String) ? payload : Legion::JSON.dump(payload)
        exchange = default_exchange.cached_instance || default_exchange.new
        exchange.publish(encoded, routing_key: routing_key, **opts)
        true
      rescue StandardError
        false
      end
    end
  end
end
