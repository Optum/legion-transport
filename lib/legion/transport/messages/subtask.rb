require 'legion/transport/exchanges/task'

module Legion
  module Transport
    module Messages
      class SubTask < Legion::Transport::Message
        def exchange
          Legion::Transport::Exchanges::Task
        end

        def message
          {
            transformation: @options[:transformation] || '{}',
            conditions: @options[:conditions] || '{}',
            results: @options[:results] || '{}'
          }
        end

        def routing_key # rubocop:disable Metrics/AbcSize
          if @options[:conditions].is_a?(String) && @options[:conditions].length > 2
            'task.subtask.conditioner'
          elsif @options[:transformation].is_a?(String) && @options[:transformation].length > 2
            'task.subtask.transform'
          elsif @options[:function_id].is_a? Integer
            function = Legion::Data::Model::Function[@options[:function_id]]
            "#{function.runner.extension.values[:exchange]}.#{function.runner.values[:queue]}.#{function.values[:name]}"
          end
        end

        def validate
          raise TypeError unless @options[:function].is_a? String

          @valid = true
        end
      end
    end
  end
end
