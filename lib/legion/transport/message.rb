# frozen_string_literal: true

module Legion
  module Transport
    class Message
      include Legion::Transport::Common

      def initialize(**options)
        @options = options
        validate
      end

      def self.max_payload_bytes
        Legion::Settings[:transport][:max_payload_bytes]
      rescue StandardError
        1_048_576
      end

      def publish(options = @options)
        raise unless @valid

        validate_payload_size
        ex_class = exchange
        exchange_dest = if ex_class.respond_to?(:cached_instance)
                          ex_class.cached_instance || ex_class.new
                        elsif ex_class.respond_to?(:new)
                          ex_class.new
                        else
                          ex_class
                        end
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
        ex_name = exchange_dest.respond_to?(:name) ? exchange_dest.name : exchange_dest.to_s
        Legion::Logging.debug "Published to exchange=#{ex_name} routing_key=#{routing_key || ''} class=#{self.class.name}" if defined?(Legion::Logging)
      rescue Bunny::ConnectionClosedError, Bunny::ChannelAlreadyClosed, Bunny::ChannelError,
             Bunny::NetworkErrorWrapper, IOError, Timeout::Error => e
        spool_message(e)
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
          Legion::Logging.debug "Message encrypted with content_encoding=encrypted/cs class=#{self.class.name}" if defined?(Legion::Logging)
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

      def headers
        @options[:headers] ||= Concurrent::Hash.new
        @options[:headers]['legion_protocol_version'] ||= '2.0'
        inject_region_header
        inject_legion_region_header
        %i[task_id relationship_id trigger_namespace_id trigger_function_id parent_id master_id runner_namespace runner_class namespace_id function_id function
           chain_id debug].each do |header|
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

      private

      def validate_payload_size
        limit = self.class.max_payload_bytes
        payload = Legion::JSON.dump(message)
        size = payload.bytesize
        return if size <= limit

        raise Legion::Transport::PayloadTooLarge,
              "message payload is #{size} bytes, exceeds limit of #{limit} bytes"
      end

      def inject_region_header
        region = begin
          Legion::Settings[:transport][:region]
        rescue StandardError => e
          Legion::Logging.debug("Message#inject_region_header region lookup failed: #{e.message}") if defined?(Legion::Logging)
          nil
        end
        return if region.nil?

        @options[:headers]['x-legion-region'] = region
        affinity = @options[:region_affinity] || 'prefer_local'
        @options[:headers]['x-legion-region-affinity'] = affinity
      end

      def inject_legion_region_header
        return unless defined?(Legion::Region) &&
                      Legion::Region.respond_to?(:current) &&
                      Legion::Region.current

        @options[:headers]['region'] = Legion::Region.current
        @options[:headers]['region_affinity'] = @options[:region_affinity] ||
                                                (defined?(Legion::Settings) && Legion::Settings.dig(:region, :default_affinity)) ||
                                                'prefer_local'
      end

      def spool_message(error)
        return unless defined?(Legion::Transport::Spool)

        Legion::Transport::Spool.write(
          exchange:    exchange_name_for_spool,
          routing_key: routing_key || '',
          payload:     message
        )
        Legion::Logging.debug { "Message spooled due to: #{error.message}" } if defined?(Legion::Logging)
      rescue StandardError => e
        Legion::Logging.warn { "Spool write failed: #{e.message}" } if defined?(Legion::Logging)
      end

      def exchange_name_for_spool
        ex = exchange
        ex.respond_to?(:name) ? ex.name : ex.to_s
      rescue StandardError => e
        Legion::Logging.warn("Message#exchange_name_for_spool failed: #{e.message}") if defined?(Legion::Logging)
        self.class.name
      end
    end
  end
end

Dir["#{__dir__}/messages/*.rb"].each { |file| require file }
