require 'legion/transport/exchanges/task'

module Legion
  module Transport
    module Messages
      class TaskLog < Legion::Transport::Message
        def routing_key
          "task.logs.create.#{@options[:task_id]}"
        end

        def exchange
          Legion::Transport::Exchanges::Task
        end

        def message
          @options[:function] = 'add_log'
          @options[:runner_class] = 'Legion::Extensions::Tasker::Runners::Log'
          @options
        end

        def generate_task?
          false
        end

        def validate
          @options[:task_id] = @options[:task_id].to_i if @options[:task_id].is_a? String
          unless @options[:task_id].is_a? Integer
            raise "task_id must be an integer but is #{@options[:task_id].class}(#{@options[:task_id]})"
          end

          @valid = true
        end
      end
    end
  end
end
