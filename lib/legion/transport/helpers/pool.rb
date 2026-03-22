# frozen_string_literal: true

module Legion
  module Transport
    module Helpers
      class Pool
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
                return conn
              end

              total = @available.size + @in_use.size
              if total < @size
                conn = @factory.call
                @in_use << conn
                return conn
              end

              remaining = deadline - Time.now
              raise Legion::Transport::PoolTimeout, 'timed out waiting for available connection' if remaining <= 0

              @condition.wait(@mutex, remaining)
            end
          end
        end

        def checkin(connection)
          @mutex.synchronize do
            @in_use.delete(connection)
            @available << connection if connection.respond_to?(:open?) && connection.open?
            @condition.signal
          end
        end

        def size
          @mutex.synchronize { @available.size + @in_use.size }
        end

        def shutdown
          @mutex.synchronize do
            (@available + @in_use).each do |conn|
              conn.close rescue nil # rubocop:disable Style/RescueModifier
            end
            @available.clear
            @in_use.clear
          end
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
