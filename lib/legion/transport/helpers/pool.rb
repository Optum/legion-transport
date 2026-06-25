# frozen_string_literal: true

require 'legion/logging/helper'

module Legion
  module Transport
    module Helpers
      class Pool
        include Legion::Logging::Helper

        def initialize(size: 1, timeout: 5, &block)
          @size        = size
          @timeout     = timeout
          @factory     = block
          @available   = []
          @in_use      = []
          @mutex       = Mutex.new
          @condition   = ConditionVariable.new
        end

        def checkout
          deadline = Time.now + @timeout

          @mutex.synchronize do
            loop do
              @available.reject! { |c| c.respond_to?(:closed?) && c.closed? }

              if (conn = @available.pop)
                @in_use << conn
                log.debug "Pool checkout (available=#{@available.size} in_use=#{@in_use.size})"
                return conn
              end

              total = @available.size + @in_use.size
              if total < @size
                conn = @factory.call
                @in_use << conn
                log.debug "Pool checkout new connection (available=#{@available.size} in_use=#{@in_use.size})"
                return conn
              end

              remaining = deadline - Time.now
              if remaining <= 0
                log.warn "Pool timeout after #{@timeout}s (size=#{@size} in_use=#{@in_use.size})"
                raise Legion::Transport::PoolTimeout, 'timed out waiting for available connection'
              end

              @condition.wait(@mutex, remaining)
            end
          end
        end

        def checkin(connection)
          @mutex.synchronize do
            @in_use.delete(connection)
            @available << connection if connection.respond_to?(:open?) && connection.open?
            log.debug "Pool checkin (available=#{@available.size} in_use=#{@in_use.size})"
            @condition.signal
          end
        end

        def size
          @mutex.synchronize { @available.size + @in_use.size }
        end

        def shutdown
          @mutex.synchronize do
            (@available + @in_use).each do |conn|
              conn.close
            rescue StandardError => e
              handle_exception(e, level: :warn, handled: true, operation: 'transport.pool.shutdown', size: @size)
            end
            @available.clear
            @in_use.clear
          end
          log.info "Pool shutdown complete size=#{@size}"
        end

        def connected?
          @mutex.synchronize do
            (@available + @in_use).any? { |c| c.respond_to?(:open?) && c.open? }
          end
        end
      end
    end
  end
end
