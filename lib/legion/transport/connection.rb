# frozen_string_literal: true

require 'concurrent-ruby'

module Legion
  module Transport
    module Connection
      class << self
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
              begin
                conn_settings = Legion::Settings[:transport][:connection].dup
                resolved = conn_settings.delete(:resolved_hosts) || []

                bunny_opts = conn_settings.merge(
                  connection_name: connection_name,
                  logger:          Legion::Transport.logger,
                  log_level:       :warn
                )

                if resolved.length > 1
                  hosts = resolved.map { |h| { host: h.split(':').first, port: h.split(':').last.to_i } }
                  bunny_opts.delete(:host)
                  bunny_opts.delete(:port)
                  bunny_opts[:hosts] = hosts
                end

                connector.new(bunny_opts)
              end
            )
            @channel_thread = Concurrent::ThreadLocalVar.new(nil)
            session.start
            session.create_channel(nil, settings[:channel][:session_worker_pool_size])
                   .basic_qos(settings[:prefetch], true)
            Legion::Settings[:transport][:connected] = true
          end

          session.on_blocked { Legion::Transport.logger.warn('Legion::Transport is being blocked by RabbitMQ!') } if session.respond_to? :on_blocked

          if session.respond_to? :on_unblocked
            session.on_unblocked do
              Legion::Transport.logger.info('Legion::Transport is no longer being blocked by RabbitMQ')
            end
          end

          if session.respond_to? :after_recovery_completed
            session.after_recovery_completed do
              Legion::Transport.logger.info('Legion::Transport has completed recovery')
            end
          end

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
      end
    end
  end
end
