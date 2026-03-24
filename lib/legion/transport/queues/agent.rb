# frozen_string_literal: true

module Legion
  module Transport
    module Queues
      class Agent < Legion::Transport::Queue
        def initialize(agent_id: nil, **)
          @agent_id = agent_id
          super(**)
        end

        def queue_name
          if @agent_id
            "agent.#{@agent_id}"
          else
            "agent.#{Legion::Settings['client']['name']}"
          end
        end

        def queue_options
          { durable: false, auto_delete: true, arguments: { 'x-dead-letter-exchange': 'agent.dlx', 'x-queue-type': 'classic' } }
        end
      end
    end
  end
end
