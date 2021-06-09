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

        def setup(connection_name: 'Legion', **) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
          Legion::Transport.logger.info("Using transport connector: #{Legion::Transport::CONNECTOR}")

          if @session.respond_to?(:value) && session.respond_to?(:closed?) && session.closed?
            @channel_thread = Concurrent::ThreadLocalVar.new(nil)
          elsif @session.respond_to?(:value) && session.respond_to?(:closed?) && session.open?
            nil
          elsif Legion::Transport::TYPE == 'march_hare'
            @session ||= Concurrent::AtomicReference.new(
              MarchHare.connect(host: settings[:connection][:host],
                                vhost: settings[:connection][:vhost],
                                user: settings[:connection][:user],
                                password: settings[:connection][:password],
                                port: settings[:connection][:port])
            )
            @channel_thread = Concurrent::ThreadLocalVar.new(nil)
            session.start
            session.create_channel.basic_qos(settings[:prefetch])
            Legion::Settings[:transport][:connected] = true
          else
            @session ||= Concurrent::AtomicReference.new(
              connector.new(
                Legion::Settings[:transport][:connection],
                connection_name: connection_name,
                logger: Legion::Transport.logger,
                log_level: :info
              )
            )
            @channel_thread = Concurrent::ThreadLocalVar.new(nil)
            session.start
            session.create_channel(nil, settings[:channel][:session_worker_pool_size])
                   .basic_qos(settings[:prefetch], true)
            Legion::Settings[:transport][:connected] = true
          end

          if session.respond_to? :on_blocked
            session.on_blocked { Legion::Transport.logger.warn('Legion::Transport is being blocked by RabbitMQ!') }
          end

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

        def channel # rubocop:disable Metrics/AbcSize
          return @channel_thread.value if !@channel_thread.value.nil? && @channel_thread.value.open?

          @channel_thread.value = session.create_channel(nil, settings[:channel][:default_worker_pool_size], false, 10)
          if Legion::Transport::TYPE == 'march_hare'
            @channel_thread.value.basic_qos(settings[:prefetch])
          else
            @channel_thread.value.prefetch(settings[:prefetch])
          end
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
