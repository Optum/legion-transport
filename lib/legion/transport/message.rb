module Legion
  module Transport
    class Message
      include Legion::Transport::Common

      def initialize(**options)
        @options = options
        validate
      end

      def publish(options = @options) # rubocop:disable Metrics/AbcSize
        raise unless @valid

        exchange_dest = exchange.respond_to?(:new) ? exchange.new : exchange
        exchange_dest.publish(encode_message,
                              routing_key: routing_key || '',
                              content_type: options[:content_type] || content_type,
                              content_encoding: options[:content_encoding] || content_encoding,
                              type: options[:type] || type,
                              priority: options[:priority] || priority,
                              expiration: options[:expiration] || expiration,
                              headers: headers,
                              persistent: persistent,
                              message_id: message_id,
                              timestamp: timestamp)
      end

      def app_id
        @options[:app_id] if @options.key? :app_id

        'legion'
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

      # ID of the message that this message is a reply to
      def correlation_id
        nil
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

      def message
        @options
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
        Legion::Settings[:transport][:messages][:encrypt] && Legion::Settings[:crypt][:cs_encrypt_ready]
      end

      def exchange_name
        lex = self.class.ancestors.first.to_s.split('::')[2].downcase
        "Legion::Extensions::#{lex.capitalize}::Transport::Exchanges::#{lex.capitalize}"
      end

      def exchange
        Kernel.const_get(exchange_name)
      end

      def headers
        @options[:headers] ||= Concurrent::Hash.new
        %i[task_id relationship_id trigger_namespace_id trigger_function_id parent_id master_id runner_namespace runner_class namespace_id function_id function chain_id debug].each do |header| # rubocop:disable Layout/LineLength
          next unless @options.key? header

          @options[:headers][header] = @options[header].to_s
        end
        @options[:headers]
      rescue StandardError => e
        Legion::Transport.logger.error e.message
        Legion::Transport.logger.error e.backtrace
      end

      def priority
        0
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

Dir["#{__dir__}/messages/*.rb"].sort.each { |file| require file }
