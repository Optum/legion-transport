module Legion
  module Transport
    module Queues
      class Node < Legion::Transport::Queue
        def queue_name
          "node.#{Legion::Settings['client']['name']}"
        end

        def queue_options
          { durable: false, auto_delete: true, arguments: { 'x-dead-letter-exchange': 'node.dlx' } }
        end
      end
    end
  end
end
