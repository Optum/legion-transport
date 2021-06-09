module Legion
  module Transport
    class Queue < Legion::Transport::CONNECTOR::Queue
      include Legion::Transport::Common

      def initialize(queue = queue_name, options = {})
        retries ||= 0
        @options = options
        super(channel, queue, options_builder(default_options, queue_options, options))
      rescue Legion::Transport::CONNECTOR::PreconditionFailed
        retries.zero? ? retries = 1 : raise
        recreate_queue(queue)
        retry
      end

      def recreate_queue(queue)
        Legion::Transport.logger.warn "Queue:#{queue} exists with wrong parameters, deleting and creating"
        queue = ::Bunny::Queue.new(Legion::Transport::Connection.channel, queue, no_declare: true, passive: true)
        queue.delete(if_empty: true)
      end

      def default_options
        hash = Concurrent::Hash.new
        hash[:manual_ack] = true
        hash[:durable] = true
        hash[:exclusive] = false
        hash[:block] = false
        hash[:auto_delete] = false
        hash[:arguments] = {
          'x-max-priority': 255,
          'x-overflow': 'reject-publish',
          'x-dead-letter-exchange': "#{self.class.ancestors.first.to_s.split('::')[2].downcase}.dlx"
        }
        hash
      end

      def queue_options
        Concurrent::Hash.new
      end

      def queue_name
        ancestor = self.class.ancestors.first.to_s.split('::')
        name = if ancestor[5].scan(/[A-Z]/).length > 1
                 ancestor[5].gsub!(/(.)([A-Z])/, '\1_\2').downcase!
               else
                 ancestor[5].downcase!
               end
        "#{ancestor[2].downcase}.#{name}"
      end

      def delete(options = { if_unused: true, if_empty: true })
        super(options)
        true
      rescue Legion::Transport::CONNECTOR::PreconditionFailed
        false
      end

      def acknowledge(delivery_tag)
        channel.acknowledge(delivery_tag)
      end

      def reject(delivery_tag, requeue: false)
        channel.reject(delivery_tag, requeue)
      end
    end
  end
end

require_relative 'queues/node'
require_relative 'queues/node_status'
require_relative 'queues/task_log'
require_relative 'queues/task_update'
