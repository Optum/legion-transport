module Legion
  module Transport
    module Queues
      class TaskUpdate < Legion::Transport::Queue
        def queue_name
          'task.update'
        end

        def queue_options
          hash = {}
          hash[:manual_ack] = true
          hash[:durable] = true
          hash[:exclusive] = false
          hash[:block] = false
          hash[:arguments] = { 'x-dead-letter-exchange': 'task.dlx' }
          hash
        end
      end
    end
  end
end
