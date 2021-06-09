require 'legion/transport/exchanges/task'

module Legion
  module Exception
    class InvalidTaskStatus < ArgumentError
      # exception class
    end

    class InvalidTaskId < ArgumentError
      # exception class
    end
  end
end

module Legion
  module Transport
    module Messages
      class TaskUpdate < Legion::Transport::Message
        def routing_key
          'task.update'
        end

        def exchange
          Legion::Transport::Exchanges::Task
        end

        def valid_status
          conditioner = ['conditioner.queued', 'conditioner.failed', 'conditioner.exception']
          transformer = ['transformer.queued', 'transformer.succeeded', 'transformer.exception']
          task = ['task.scheduled', 'task.queued', 'task.completed', 'task.exception', 'task.delayed']
          conditioner + transformer + task
        end
      end
    end
  end
end
