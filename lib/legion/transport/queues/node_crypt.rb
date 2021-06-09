module Legion
  module Transport
    module Queues
      class NodeCrypt < Legion::Transport::Queue
        def queue_name
          'node.status'
        end

        def queue_options
          hash = {}
          hash[:manual_ack] = true
          hash[:durable] = true
          hash[:exclusive] = false
          hash[:block] = false
          hash[:arguments] = { 'x-dead-letter-exchange': 'node.dlx' }
          hash
        end
      end
    end
  end
end
