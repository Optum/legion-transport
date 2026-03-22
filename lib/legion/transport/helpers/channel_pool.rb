# frozen_string_literal: true

module Legion
  module Transport
    module Helpers
      class ChannelPool
        def initialize(connection:, size: 10, prefetch: 2)
          @connection = connection
          @size       = size
          @prefetch   = prefetch
          @available  = []
          @in_use     = []
          @mutex      = Mutex.new
        end

        def borrow
          @mutex.synchronize do
            purge_closed_unsafe

            if (ch = @available.pop)
              @in_use << ch
              Legion::Logging.debug "ChannelPool borrow reused (available=#{@available.size} in_use=#{@in_use.size})" if defined?(Legion::Logging)
              return ch
            end

            total = @available.size + @in_use.size
            return nil if total >= @size

            ch = @connection.create_channel
            ch.prefetch(@prefetch) if ch.respond_to?(:prefetch)
            @in_use << ch
            Legion::Logging.debug "ChannelPool borrow new channel (available=#{@available.size} in_use=#{@in_use.size})" if defined?(Legion::Logging)
            ch
          end
        end

        def return(channel)
          @mutex.synchronize do
            @in_use.delete(channel)
            return unless channel.respond_to?(:open?) && channel.open?
            return if (@available.size + @in_use.size) >= @size

            @available << channel
            Legion::Logging.debug "ChannelPool return (available=#{@available.size} in_use=#{@in_use.size})" if defined?(Legion::Logging)
          end
        end

        def purge_closed
          @mutex.synchronize { purge_closed_unsafe }
        end

        def close_all
          @mutex.synchronize do
            total = @available.size + @in_use.size
            (@available + @in_use).each do |ch|
              ch.close
            rescue StandardError => e
              Legion::Logging.debug("ChannelPool#close_all channel close failed: #{e.message}") if defined?(Legion::Logging)
            end
            @available.clear
            @in_use.clear
            Legion::Logging.info "ChannelPool closed #{total} channel(s)" if defined?(Legion::Logging)
          end
        end

        def size
          @mutex.synchronize { @available.size + @in_use.size }
        end

        private

        def purge_closed_unsafe
          @available.reject! { |c| !c.respond_to?(:open?) || !c.open? }
          @in_use.reject!    { |c| !c.respond_to?(:open?) || !c.open? }
        end
      end
    end
  end
end
