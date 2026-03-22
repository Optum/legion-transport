# frozen_string_literal: true

require 'concurrent-ruby'
require_relative 'connection/ssl'

module Legion
  module Transport
    module Connection
      class << self
        include Legion::Transport::Connection::SSL

        def settings
          Legion::Settings[:transport]
        end

        def new
          clone
        end

        def connector
          Legion::Transport::CONNECTOR
        end

        def reconnect(connection_name: 'Legion', **)
          @session = nil
          @channel_thread = Concurrent::ThreadLocalVar.new(nil)
          setup(connection_name: connection_name)
        end

        def setup(connection_name: 'Legion', **)
          Legion::Transport.logger.info("Using transport connector: #{Legion::Transport::CONNECTOR}")

          if @session.respond_to?(:value) && session.respond_to?(:closed?) && session.closed?
            @channel_thread = Concurrent::ThreadLocalVar.new(nil)
          elsif @session.respond_to?(:value) && session.respond_to?(:closed?) && session.open?
            nil
          else
            @session ||= Concurrent::AtomicReference.new(
              create_session_with_failover(connection_name: connection_name)
            )
            @channel_thread = Concurrent::ThreadLocalVar.new(nil)
            session.start
            session.create_channel(nil, settings[:channel][:session_worker_pool_size])
                   .basic_qos(settings[:prefetch], true)
            Legion::Settings[:transport][:connected] = true
          end

          register_session_callbacks
          apply_quorum_policy_if_enabled
          true
        end

        def channel
          return @channel_thread.value if !@channel_thread.value.nil? && @channel_thread.value.open?

          @channel_thread.value = session.create_channel(nil, settings[:channel][:default_worker_pool_size], false, 10)
          @channel_thread.value.prefetch(settings[:prefetch])
          @channel_thread.value
        end

        def session
          nil if @session.nil?
          @session.value
        end

        def channel_thread
          channel
        end

        def channel_open?
          channel.open?
        rescue StandardError
          false
        end

        def session_open?
          session.open?
        rescue StandardError
          false
        end

        def shutdown
          session.close
          @session = nil
        end

        private

        def create_session_with_failover(connection_name:)
          opts = build_bunny_opts(connection_name: connection_name)
          hosts = opts[:hosts] || [{ host: opts[:host] || '127.0.0.1', port: opts[:port] || 5672 }]
          last_error = nil

          hosts.each do |host_entry|
            attempt_opts = opts.dup
            if host_entry.is_a?(Hash)
              attempt_opts[:host] = host_entry[:host]
              attempt_opts[:port] = host_entry[:port]
            end
            attempt_opts.delete(:hosts)

            return connector.new(attempt_opts)
          rescue Bunny::TCPConnectionFailed, Bunny::PossibleAuthenticationFailureError, Errno::ECONNREFUSED => e
            last_error = e
            host_desc = host_entry.is_a?(Hash) ? "#{host_entry[:host]}:#{host_entry[:port]}" : host_entry
            Legion::Transport.logger.warn("Connection failed to #{host_desc}: #{e.message}")
          end

          raise Legion::Transport::ClusterUnavailable, "All cluster nodes exhausted: #{last_error&.message}" if defined?(Legion::Transport::ClusterUnavailable)

          raise last_error || StandardError.new('No cluster nodes available')
        end

        def register_session_callbacks
          session.on_blocked { Legion::Transport.logger.warn('Legion::Transport is being blocked by RabbitMQ!') } if session.respond_to?(:on_blocked)

          if session.respond_to?(:on_unblocked)
            session.on_unblocked do
              Legion::Transport.logger.info('Legion::Transport is no longer being blocked by RabbitMQ')
            end
          end

          return unless session.respond_to?(:after_recovery_completed)

          session.after_recovery_completed do
            Legion::Transport.logger.info('Legion::Transport has completed recovery')
          end
        end

        def apply_quorum_policy_if_enabled
          return unless defined?(Legion::Transport::Helpers::Policy)

          Legion::Transport::Helpers::Policy.apply_quorum_policy!
        rescue StandardError
          nil
        end

        def build_bunny_opts(connection_name:)
          conn_settings = Legion::Settings[:transport][:connection].dup
          resolved = conn_settings.delete(:resolved_hosts) || []

          cluster_nodes = Array(Legion::Settings[:transport][:cluster_nodes])
          all_hosts = (resolved + cluster_nodes).uniq
          all_hosts.shuffle! if all_hosts.length > 1

          opts = conn_settings.merge(
            connection_name: connection_name,
            logger:          Legion::Transport.logger,
            log_level:       :warn
          )

          if all_hosts.length > 1
            opts[:hosts] = all_hosts.map { |h| { host: h.split(':').first, port: h.split(':').last.to_i } }
            opts.delete(:host)
            opts.delete(:port)
          end

          opts.merge!(tls_options)
          opts
        end
      end
    end
  end
end
