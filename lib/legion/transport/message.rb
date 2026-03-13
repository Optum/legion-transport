# frozen_string_literal: true

module Legion
  module Transport
    class Message
      include Legion::Transport::Common

      def initialize(**options)
        @options = options
        validate
      end

      def publish(options = @options)
        raise unless @valid

        exchange_dest = exchange.respond_to?(:new) ? exchange.new : exchange
        exchange_dest.publish(encode_message,
                              routing_key:      routing_key || '',
                              content_type:     options[:content_type] || content_type,
                              content_encoding: options[:content_encoding] || content_encoding,
                              type:             options[:type] || type,
                              priority:         options[:priority] || priority,
                              expiration:       options[:expiration] || expiration,
                              headers:          headers,
                              persistent:       persistent,
                              message_id:       message_id,
                              correlation_id:   correlation_id,
                              app_id:           app_id,
                              timestamp:        timestamp)
      end

      def app_id
        @options[:app_id] || 'legion'
      end

      def message_id
        @options[:message_id] || @options[:task_id]
      end

      # user_id Sender's identifier. https://www.rabbitmq.com/extensions.html#validated-user-id
      def user_id
        @options[:user_id] || Legion::Transport.settings[:connection][:user]
      end

      def reply_to
        @options[:reply_to]
      end

      # ID of the message that this message is a reply to.
      # Links subtasks back to the parent task.
      def correlation_id
        @options[:correlation_id] || @options[:parent_id] || @options[:task_id]
      end

      def persistent
        @options[:persistent] || Legion::Transport.settings[:messages][:persistent]
      end

      def expiration
        if @options.key? :expiration
          @options[:expiration]
        elsif @options.key? :ttl
          @options[:ttl]
        elsif Legion::Transport.settings[:messages].key? :expiration
          Legion::Transport.settings[:messages][:expiration]
        end
      end

      ENVELOPE_KEYS = %i[
        headers content_type content_encoding persistent expiration
        priority app_id user_id reply_to correlation_id message_id
        routing_key exchange type
      ].freeze

      def message
        @options.except(*ENVELOPE_KEYS)
      end

      def routing_key
        @options[:routing_key] if @options.key? :routing_key
      end

      def encode_message
        message_payload = message
        message_payload = Legion::JSON.dump(message_payload) unless message_payload.is_a? String

        if encrypt?
          encrypted = Legion::Crypt.encrypt(message_payload)
          headers[:iv] = encrypted[:iv]
          @options[:content_encoding] = 'encrypted/cs'
          return encrypted[:enciphered_message]
        else
          @options[:content_encoding] = 'identity'
        end

        message_payload
      end

      def encrypt_message(message, _type = 'cs')
        Legion::Crypt.encrypt(message)
      end

      def encrypt?
        should_encrypt = if @options.key?(:encrypt)
                           @options[:encrypt]
                         else
                           Legion::Settings[:transport][:messages][:encrypt]
                         end
        should_encrypt && Legion::Settings[:crypt][:cs_encrypt_ready]
      end

      def exchange_name
        lex = self.class.ancestors.first.to_s.split('::')[2].downcase
        "Legion::Extensions::#{lex.capitalize}::Transport::Exchanges::#{lex.capitalize}"
      end

      def exchange
        Kernel.const_get(exchange_name)
      end

      HEADER_KEYS = %i[
        task_id relationship_id trigger_namespace_id trigger_function_id
        parent_id master_id runner_namespace runner_class namespace_id
        function_id function chain_id debug
      ].freeze

      def headers
        @options[:headers] ||= Concurrent::Hash.new
        HEADER_KEYS.each do |header|
          next unless @options.key? header

          value = @options[header]
          @options[:headers][header] = case value
                                       when Integer, Float, TrueClass, FalseClass
                                         value
                                       else
                                         value.to_s
                                       end
        end
        @options[:headers]
      rescue StandardError => e
        Legion::Transport.logger.error e.message
        Legion::Transport.logger.error e.backtrace
      end

      def priority
        @options[:priority] || Legion::Transport.settings[:messages][:priority] || 0
      end

      def content_type
        'application/json'
      end

      def content_encoding
        'identity'
      end

      def type
        'task'
      end

      def timestamp
        Time.now.to_i
      end

      def validate
        @valid = true
      end

      def channel
        Legion::Transport::Connection.channel
      end
    end
  end
end

Dir["#{__dir__}/messages/*.rb"].each { |file| require file }
