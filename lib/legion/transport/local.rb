# frozen_string_literal: true

module Legion
  module Transport
    module Local
      @queues = {}
      @subscribers = {}
      @mutex = Mutex.new

      class << self
        def setup
          Legion::Logging.info 'Legion::Transport::Local initialized (in-memory mode)' if defined?(Legion::Logging)
        end

        def publish(_exchange_name, routing_key, payload, **)
          @mutex.synchronize do
            @queues[routing_key] ||= []
            @queues[routing_key] << payload

            (@subscribers[routing_key] || []).each do |callback|
              callback.call(payload)
            end
          end
          Legion::Logging.debug "Local published routing_key=#{routing_key}" if defined?(Legion::Logging)
          { published: true, routing_key: routing_key }
        end

        def subscribe(queue_name, &block)
          @mutex.synchronize do
            @subscribers[queue_name] ||= []
            @subscribers[queue_name] << block

            (@queues[queue_name] || []).each { |msg| block.call(msg) }
            @queues[queue_name] = []
          end
          Legion::Logging.debug "Local subscribed queue=#{queue_name}" if defined?(Legion::Logging)
          { subscribed: true, queue: queue_name }
        end

        def queue_depth(queue_name)
          @mutex.synchronize { (@queues[queue_name] || []).size }
        end

        def reset!
          Legion::Logging.info 'Legion::Transport::Local shut down (queues cleared)' if defined?(Legion::Logging)
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
