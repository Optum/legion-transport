# frozen_string_literal: true

module Legion
  module Transport
    module Queues
      class Node < Legion::Transport::Queue
        def queue_name
          "node.#{Legion::Settings['client']['name']}"
        end

        def queue_options
          { durable: false, auto_delete: true, exclusive: true, arguments: { 'x-dead-letter-exchange': 'node.dlx', 'x-queue-type': 'classic' } }
        end
      end
    end
  end
end
