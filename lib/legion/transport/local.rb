# frozen_string_literal: true

require 'legion/logging/helper'

module Legion
  module Transport
    module Local
      @queues = {}
      @subscribers = {}
      @mutex = Mutex.new

      class << self
        include Legion::Logging::Helper

        def setup
          log.info 'Legion::Transport::Local initialized (in-memory mode)'
        end

        def publish(_exchange_name, routing_key, payload, **)
          @mutex.synchronize do
            @queues[routing_key] ||= []
            @queues[routing_key] << payload

            (@subscribers[routing_key] || []).each do |callback|
              callback.call(payload)
            end
          end
          log.debug "Local published routing_key=#{routing_key}"
          { published: true, routing_key: routing_key }
        end

        def subscribe(queue_name, &block)
          @mutex.synchronize do
            @subscribers[queue_name] ||= []
            @subscribers[queue_name] << block

            (@queues[queue_name] || []).each { |msg| block.call(msg) }
            @queues[queue_name] = []
          end
          log.info "Local subscribed queue=#{queue_name}"
          { subscribed: true, queue: queue_name }
        end

        def queue_depth(queue_name)
          @mutex.synchronize { (@queues[queue_name] || []).size }
        end

        def reset!
          log.info 'Legion::Transport::Local shut down (queues cleared)'
          @mutex.synchronize do
            @queues.clear
            @subscribers.clear
          end
        end

        def active?
          true
        end
      end
    end
  end
end
