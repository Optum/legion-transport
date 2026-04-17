# frozen_string_literal: true

require 'legion/transport/exchanges/task'

module Legion
  module Exception
    class InvalidTaskStatus < ArgumentError; end
    class InvalidTaskId < ArgumentError; end
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

        def validate
          raise Legion::Exception::InvalidTaskId unless @options[:task_id].is_a?(Integer) && @options[:task_id].positive?
          raise Legion::Exception::InvalidTaskStatus unless valid_status.include?(@options[:status])

          @valid = true
        end
      end
    end
  end
end
