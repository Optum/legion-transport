require 'legion/transport/exchanges/task'

module Legion
  module Transport
    module Messages
      class CheckSubtask < Legion::Transport::Message
        def exchange
          Legion::Transport::Exchanges::Task
        end

        def exchange_name
          'Legion::Transport::Exchanges::Task'
        end

        def routing_key
          'task.subtask.check'
        end

        def validate
          @valid = true
        end
      end
    end
  end
end
