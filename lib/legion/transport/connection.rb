# frozen_string_literal: true

require 'concurrent-ruby'
require 'timeout'
require_relative 'connection/ssl'
require_relative 'connection/vault'

module Legion
  module Transport
    module Connection
      RECOVERY_WINDOW = 60
      MAX_RECOVERIES_PER_WINDOW = 5

      class << self
        include Legion::Transport::Connection::SSL
        include Legion::Transport::Connection::Vault

        def lite_mode?
          Legion::Transport::TYPE == 'local'
        end

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
          return setup_lite if lite_mode?

          pool_size = settings[:connection_pool_size].to_i
          if pool_size > 1
            setup_pool(pool_size: pool_size, connection_name: connection_name)
          elsif @session.respond_to?(:value) && session.respond_to?(:closed?) && session.closed?
            @channel_thread = Concurrent::ThreadLocalVar.new(nil)
          elsif @session.respond_to?(:value) && session.respond_to?(:closed?) && session.open?
            nil
          else
            @session ||= Concurrent::AtomicReference.new(
              create_session_with_failover(connection_name: connection_name)
            )
            @channel_thread = Concurrent::ThreadLocalVar.new(nil)
            session.start
            qos_channel = session.create_channel(nil, settings[:channel][:session_worker_pool_size])
            apply_qos_and_close(qos_channel)
            Legion::Settings[:transport][:connected] = true
            if defined?(Legion::Logging)
              host  = settings.dig(:connection, :host) || '127.0.0.1'
              port  = settings.dig(:connection, :port) || 5672
              user  = settings.dig(:connection, :user) || 'guest'
              vhost = settings.dig(:connection, :vhost) || '/'
              Legion::Logging.info "Connected to amqp://#{user}@#{host}:#{port}/#{vhost}"
            end
          end

          register_session_callbacks
          reset_log_channel
          apply_quorum_policy_if_enabled
          true
        end

        def channel
          # Build threads route to build session
          return build_channel if Thread.current[:legion_build_session] && @build_session

          if @pool
            sess = @pool.checkout
            ch = sess.create_channel(nil, settings[:channel][:default_worker_pool_size], false, 10)
            ch.prefetch(settings[:prefetch])
            @pool.checkin(sess)
            return ch
          end

          return @channel_thread.value if !@channel_thread.value.nil? && @channel_thread.value.open?

          @channel_thread.value = session.create_channel(nil, settings[:channel][:default_worker_pool_size], false, 10)
          @channel_thread.value.prefetch(settings[:prefetch])
          Legion::Logging.debug "Channel created for thread #{Thread.current.object_id}" if defined?(Legion::Logging)
          @channel_thread.value
        end

        def session
          return nil if @session.nil?

          @session.value
        end

        def channel_thread
          channel
        end

        def channel_open?
          channel.open?
        rescue StandardError => e
          Legion::Logging.debug("Connection#channel_open? failed: #{e.message}") if defined?(Legion::Logging)
          false
        end

        def session_open?
          session.open?
        rescue StandardError => e
          Legion::Logging.debug("Connection#session_open? failed: #{e.message}") if defined?(Legion::Logging)
          false
        end

        def shutdown
          Legion::Logging.info 'Transport connection shutting down' if defined?(Legion::Logging)
          @shutting_down = true
          close_build_session

          if @pool
            @pool.shutdown
            @pool = nil
          end

          return unless @session

          if lite_mode?
            session&.close
            @session = nil
            return
          end

          s = session
          return unless s

          tear_down_session(s)
        rescue StandardError => e
          Legion::Logging.warn("Transport shutdown error: #{e.message}") if defined?(Legion::Logging)
        ensure
          @log_channel = nil
          @session = nil
          @shutting_down = false
        end

        def force_reconnect(connection_name: 'Legion')
          return if @shutting_down

          Legion::Transport.logger.warn('Force reconnecting: pathological recovery loop detected')
          old = session
          @session = nil
          @channel_thread = Concurrent::ThreadLocalVar.new(nil)
          @recovery_timestamps = []

          tear_down_session(old) if old
          setup(connection_name: connection_name)

          Array(@reconnect_callbacks).each do |cb|
            cb.call
          rescue StandardError => e
            Legion::Transport.logger.warn("Reconnect callback failed: #{e.message}")
          end
        rescue StandardError => e
          Legion::Transport.logger.error("force_reconnect failed: #{e.message}")
        end

        def on_force_reconnect(&block)
          @reconnect_callbacks ||= []
          @reconnect_callbacks << block
        end

        def open_build_session(connection_name: 'Legion::Build')
          return if lite_mode?
          return if @build_session

          @build_session = Concurrent::AtomicReference.new(
            create_session_with_failover(connection_name: connection_name)
          )
          @build_session.value.start
          @build_channel_thread = Concurrent::ThreadLocalVar.new(nil)
          Legion::Logging.info 'Build session opened' if defined?(Legion::Logging)
        end

        def build_channel
          return channel unless @build_session
          return @build_channel_thread.value if @build_channel_thread.value&.open?

          @build_channel_thread.value = @build_session.value.create_channel(
            nil, settings[:channel][:default_worker_pool_size], false, 10
          )
          @build_channel_thread.value.prefetch(settings[:prefetch])
          @build_channel_thread.value
        end

        def close_build_session
          return unless @build_session

          s = @build_session.value
          Timeout.timeout(10) { s.close } if s&.open?
          @build_session = nil
          @build_channel_thread = nil
          Legion::Logging.info 'Build session closed (all build channels released)' if defined?(Legion::Logging)
        rescue Timeout::Error
          Legion::Logging.warn 'Build session close timed out, forcing' if defined?(Legion::Logging)
          bs = @build_session&.value
          bs&.instance_variable_get(:@transport)&.close rescue nil # rubocop:disable Style/RescueModifier
          @build_session = nil
          @build_channel_thread = nil
        rescue StandardError => e
          Legion::Logging.warn "Build session close error: #{e.message}" if defined?(Legion::Logging)
          @build_session = nil
          @build_channel_thread = nil
        end

        def build_session_open?
          @build_session&.value&.open? == true
        end

        def log_channel
          return nil if lite_mode?
          return @log_channel if @log_channel&.open?

          if session&.open?
            @log_channel&.close rescue nil # rubocop:disable Style/RescueModifier
            @log_channel = session.create_channel
            @log_channel.prefetch(1)
            @log_channel
          end
        rescue StandardError => e
          Legion::Logging.debug("Connection#log_channel recovery failed: #{e.message}") if defined?(Legion::Logging)
          nil
        end

        def create_dedicated_session(name: 'legion-dedicated')
          if lite_mode?
            # In-process transport is process-global; return the shared session so
            # that callers do not inadvertently reset all queues via Session#close.
            # Use an AtomicReference + compare_and_set so concurrent callers cannot
            # each create a separate InProcess::Session (whose #close calls Local.reset!).
            ref = (@session ||= Concurrent::AtomicReference.new(nil))

            loop do
              shared = ref.value
              return shared if shared&.open?

              s = Legion::Transport::InProcess::Session.new
              s.start
              # Install this session only if no other thread has won the race.
              return s if ref.compare_and_set(shared, s)
              # Another thread installed a session first; discard this one and retry.
            end
          end

          sess = create_session_with_failover(connection_name: name)
          sess.start
          sess
        end

        private

        def apply_qos_and_close(qos_channel)
          qos_channel.basic_qos(settings[:prefetch], true)
        ensure
          safe_close_channel(qos_channel)
        end

        def safe_close_channel(chan)
          chan&.close if chan&.open?
        rescue StandardError
          # suppress close errors to avoid masking setup errors
        end

        def reset_log_channel
          @log_channel&.close if @log_channel&.open?
        rescue StandardError => e
          Legion::Logging.debug("Connection#reset_log_channel close failed: #{e.message}") if defined?(Legion::Logging)
        ensure
          @log_channel = session.create_channel
          @log_channel.prefetch(1)
        end

        def setup_pool(pool_size:, connection_name:)
          require 'legion/transport/helpers/pool'
          @pool = Legion::Transport::Helpers::Pool.new(size: pool_size) do
            create_session_with_failover(connection_name: connection_name)
          end
          primary = @pool.checkout
          primary.start
          qos_channel = primary.create_channel(nil, settings[:channel][:session_worker_pool_size])
          apply_qos_and_close(qos_channel)
          @pool.checkin(primary)
          @session ||= Concurrent::AtomicReference.new(primary)
          @channel_thread = Concurrent::ThreadLocalVar.new(nil)
          Legion::Settings[:transport][:connected] = true
          Legion::Logging.info "Connected via pool (size=#{pool_size})" if defined?(Legion::Logging)
        rescue StandardError => e
          @pool = nil
          raise e
        end

        def setup_lite
          require_relative 'local'
          Legion::Transport::Local.setup
          @session ||= Concurrent::AtomicReference.new(Legion::Transport::InProcess::Session.new)
          session.start unless session.open?
          @channel_thread = Concurrent::ThreadLocalVar.new(nil)
          Legion::Settings[:transport][:connected] = true
          Legion::Logging.info 'Connected via in-process transport (lite mode)' if defined?(Legion::Logging)
          true
        end

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
          @recovery_timestamps ||= []

          session.on_blocked { Legion::Transport.logger.warn('Legion::Transport is being blocked by RabbitMQ!') } if session.respond_to?(:on_blocked)

          if session.respond_to?(:on_unblocked)
            session.on_unblocked do
              Legion::Transport.logger.info('Legion::Transport is no longer being blocked by RabbitMQ')
            end
          end

          if session.respond_to?(:after_recovery_attempts_exhausted)
            session.after_recovery_attempts_exhausted do
              Legion::Transport.logger.error('Recovery attempts exhausted — forcing full reconnect')
              Thread.new { force_reconnect }
            end
          end

          return unless session.respond_to?(:after_recovery_completed)

          session.after_recovery_completed do
            Legion::Transport.logger.info('Legion::Transport has completed recovery')

            @recovery_timestamps << Time.now
            @recovery_timestamps.reject! { |t| t < Time.now - RECOVERY_WINDOW }

            if @recovery_timestamps.size >= MAX_RECOVERIES_PER_WINDOW
              Legion::Transport.logger.warn(
                "#{@recovery_timestamps.size} recoveries in #{RECOVERY_WINDOW}s — forcing full reconnect"
              )
              Thread.new { force_reconnect }
            end
          end
        end

        def tear_down_session(sess)
          sess.instance_variable_set(:@recovering_from_network_failure, false) rescue nil # rubocop:disable Style/RescueModifier

          # Close transport socket FIRST — breaks IO.select in reader loop threads
          begin
            transport = sess.instance_variable_get(:@transport)
            transport&.close
          rescue StandardError
            nil
          end

          # Then attempt orderly close with tight timeout
          Timeout.timeout(3) { sess.close }
        rescue Timeout::Error
          Legion::Transport.logger.warn('Session close timed out, killing reader thread')
          kill_reader_threads(sess)
        rescue StandardError => e
          Legion::Transport.logger.debug("tear_down_session: #{e.message}")
        end

        def kill_reader_threads(sess)
          reader_loop = sess.instance_variable_get(:@reader_loop)
          thread = reader_loop&.instance_variable_get(:@thread)
          thread&.kill
        rescue StandardError => e
          Legion::Transport.logger.debug("kill_reader_threads: #{e.message}")
        end

        def apply_quorum_policy_if_enabled
          return unless defined?(Legion::Transport::Helpers::Policy)

          Legion::Transport::Helpers::Policy.apply_quorum_policy!
        rescue StandardError => e
          Legion::Logging.warn("Connection#apply_quorum_policy_if_enabled failed: #{e.message}") if defined?(Legion::Logging)
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
          vault_opts = vault_pki_tls_options
          opts.merge!(vault_opts) unless vault_opts.empty?
          opts
        end
      end
    end
  end
end
