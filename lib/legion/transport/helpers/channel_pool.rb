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
              return ch
            end

            total = @available.size + @in_use.size
            return nil if total >= @size

            ch = @connection.create_channel
            ch.prefetch(@prefetch) if ch.respond_to?(:prefetch)
            @in_use << ch
            ch
          end
        end

        def return(channel)
          @mutex.synchronize do
            @in_use.delete(channel)
            return unless channel.respond_to?(:open?) && channel.open?
            return if (@available.size + @in_use.size) >= @size

            @available << channel
          end
        end

        def purge_closed
          @mutex.synchronize { purge_closed_unsafe }
        end

        def close_all
          @mutex.synchronize do
            (@available + @in_use).each do |ch|
              ch.close rescue nil # rubocop:disable Style/RescueModifier
            end
            @available.clear
            @in_use.clear
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
