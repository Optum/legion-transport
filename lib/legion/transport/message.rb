# frozen_string_literal: true

require 'legion/logging/helper'

module Legion
  module Transport
    class Message
      include Legion::Transport::Common

      class << self
        include Legion::Logging::Helper
      end

      def initialize(**options)
        @options = options
        validate
      end

      def self.max_payload_bytes
        Legion::Settings[:transport][:max_payload_bytes]
      rescue StandardError => e
        handle_exception(e, level: :warn, handled: true, operation: 'transport.message.max_payload_bytes')
        1_048_576
      end

      def publish(options = nil)
        raise unless @valid

        publish_options = options ? @options.merge(options) : @options
        validate_payload_size
        ex_class = exchange
        exchange_dest = if ex_class.respond_to?(:cached_instance)
                          ex_class.cached_instance || ex_class.new
                        elsif ex_class.respond_to?(:new)
                          ex_class.new
                        else
                          ex_class
                        end
        return_state = {}
        install_return_listener(exchange_dest, publish_options, return_state)
        prepare_publisher_confirms(exchange_dest, publish_options)
        exchange_dest.publish(encode_message,
                              **publish_envelope_options(publish_options))
        result = publish_result(exchange_dest, publish_options, return_state)
        return result if return_publish_result?(publish_options)

        nil
      rescue Bunny::ConnectionClosedError, Bunny::ChannelAlreadyClosed, Bunny::ChannelError,
             Bunny::NetworkErrorWrapper, IOError, Timeout::Error => e
        handle_exception(e, level: :warn, handled: true, operation: 'transport.message.publish',
                         spooled: spool_enabled?(publish_options))
        spool_message(e, publish_options) if spool_enabled?(publish_options)
        publish_failure_result(spool_enabled?(publish_options) ? :spooled : :failed, e, publish_options)
      end

      def publish_envelope_options(options)
        {
          routing_key:      options[:routing_key] || routing_key || '',
          content_type:     options[:content_type] || content_type,
          content_encoding: options[:content_encoding] || content_encoding,
          type:             options[:type] || type,
          priority:         options[:priority] || priority,
          expiration:       options[:expiration] || expiration,
          headers:          headers,
          persistent:       options.key?(:persistent) ? options[:persistent] : persistent,
          message_id:       message_id,
          correlation_id:   correlation_id,
          reply_to:         reply_to,
          app_id:           app_id,
          timestamp:        timestamp
        }.tap do |envelope|
          envelope[:mandatory] = true if options[:mandatory] == true
        end
      end

      def publish_result(exchange_dest, options, return_state)
        confirmed_status = confirm_publish(exchange_dest, options)
        status = return_state[:returned] ? :unroutable : confirmed_status
        ex_name = exchange_dest.respond_to?(:name) ? exchange_dest.name : exchange_dest.to_s
        log.debug "Published to exchange=#{ex_name} routing_key=#{options[:routing_key] || routing_key || ''} class=#{self.class.name}"
        {
          status:            status,
          accepted:          status == :accepted,
          exchange:          ex_name,
          routing_key:       options[:routing_key] || routing_key || '',
          message_id:        message_id,
          return_reply_code: return_state[:reply_code],
          return_reply_text: return_state[:reply_text],
          correlation_id:    correlation_id
        }.compact
      end

      def prepare_publisher_confirms(exchange_dest, options)
        return unless options[:publisher_confirm] == true

        confirm_channel = publish_channel(exchange_dest)
        return unless confirm_channel.respond_to?(:confirm_select)

        confirm_channel.confirm_select
      end

      def confirm_publish(exchange_dest, options)
        return :accepted unless options[:publisher_confirm] == true

        confirm_channel = publish_channel(exchange_dest)
        return :accepted unless confirm_channel.respond_to?(:wait_for_confirms)

        timeout = options[:publish_confirm_timeout_ms]
        confirmed = if timeout
                      confirm_channel.wait_for_confirms(timeout.to_f / 1000.0)
                    else
                      confirm_channel.wait_for_confirms
                    end
        confirmed == false ? :nacked : :accepted
      rescue Timeout::Error
        :confirm_timeout
      end

      def publish_channel(exchange_dest)
        return exchange_dest.channel if exchange_dest.respond_to?(:channel)

        channel
      end

      def install_return_listener(exchange_dest, options, return_state)
        return unless options[:mandatory] == true

        return_channel = publish_channel(exchange_dest)
        return unless return_channel.respond_to?(:on_return)

        expected_correlation_id = correlation_id
        expected_message_id = message_id
        return_channel.on_return do |return_info, properties, _content|
          next if properties.respond_to?(:correlation_id) && properties.correlation_id &&
                  expected_correlation_id && properties.correlation_id != expected_correlation_id
          next if properties.respond_to?(:message_id) && properties.message_id &&
                  expected_message_id && properties.message_id != expected_message_id

          return_state[:returned] = true
          return_state[:reply_code] = return_info.reply_code if return_info.respond_to?(:reply_code)
          return_state[:reply_text] = return_info.reply_text if return_info.respond_to?(:reply_text)
        end
      end

      def spool_enabled?(options)
        options.fetch(:spool, true) != false
      end

      def return_publish_result?(options)
        options[:return_result] == true || options[:mandatory] == true || options[:publisher_confirm] == true ||
          options[:spool] == false
      end

      def publish_failure_result(status, error, options = @options)
        {
          status:         status,
          accepted:       false,
          error_class:    error.class.name,
          error:          error.message,
          routing_key:    options[:routing_key] || routing_key || '',
          message_id:     message_id,
          correlation_id: correlation_id
        }
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
        elsif Legion::Transport.settings[:messages].key? :ttl
          Legion::Transport.settings[:messages][:ttl]
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
          log.debug "Message encrypted with content_encoding=encrypted/cs class=#{self.class.name}"
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
        parts = derive_extension_parts
        "Legion::Extensions::#{parts.join('::')}::Transport::Exchanges::#{parts.first}"
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
        inject_identity_headers
        @options[:headers]
      rescue StandardError => e
        handle_exception(e, level: :error, handled: true, operation: 'transport.message.headers')
        {}
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

      def identity_process_resolved?
        defined?(Legion::Identity::Process) && Legion::Identity::Process.resolved?
      end

      def identity_headers
        id = Legion::Identity::Process.identity_hash
        {
          'x-legion-identity-canonical-name' => id[:canonical_name].to_s,
          'x-legion-identity-trust'          => id[:trust].to_s,
          'x-legion-identity-id'             => id[:id].to_s,
          'x-legion-identity-kind'           => id[:kind].to_s,
          'x-legion-identity-mode'           => id[:mode].to_s,
          'x-legion-identity-source'         => id[:source].to_s
        }
      end

      def inject_identity_headers
        return unless identity_process_resolved?

        @options[:headers].merge!(identity_headers)
      rescue LoadError, StandardError => e
        handle_exception(e, level: :warn, handled: true, operation: 'transport.message.inject_identity_headers')
      end

      def inject_region_header
        region = begin
          Legion::Settings[:transport][:region]
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: 'transport.message.inject_region_header')
          nil
        end
        return if region.nil?

        @options[:headers]['x-legion-region'] = region
        affinity = @options[:region_affinity] || 'prefer_local'
        @options[:headers]['x-legion-region-affinity'] = affinity
      end

      def inject_legion_region_header
        return unless defined?(Legion::Region) &&
                      Legion::Region.respond_to?(:current)

        default_affinity = (defined?(Legion::Settings) && Legion::Settings.dig(:region, :default_affinity)) || 'prefer_local'
        explicit_region = defined?(Legion::Settings) ? Legion::Settings.dig(:region, :current) : nil
        return if explicit_region.nil? && default_affinity == 'any'

        current_region = Legion::Region.current
        return if current_region.nil?

        @options[:headers]['region'] = current_region
        @options[:headers]['region_affinity'] = @options[:region_affinity] ||
                                                default_affinity
      end

      def spool_message(error, options = @options)
        return unless defined?(Legion::Transport::Spool)

        Legion::Transport::Spool.write(
          exchange:       exchange_name_for_spool,
          routing_key:    options[:routing_key] || routing_key || '',
          payload:        message,
          headers:        @options[:headers],
          priority:       priority,
          message_id:     message_id,
          correlation_id: correlation_id,
          persistent:     options.key?(:persistent) ? options[:persistent] : persistent
        )
        log.info("Message spooled due to: #{error.message}")
      rescue StandardError => e
        handle_exception(e, level: :warn, handled: true, operation: 'transport.message.spool_write')
      end

      def exchange_name_for_spool
        ex = exchange
        ex.respond_to?(:name) ? ex.name : ex.to_s
      rescue StandardError => e
        handle_exception(e, level: :warn, handled: true, operation: 'transport.message.exchange_name_for_spool')
        self.class.name
      end
    end
  end
end

Dir["#{__dir__}/messages/*.rb"].each { |file| require file }
