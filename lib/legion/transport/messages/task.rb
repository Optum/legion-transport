module Legion
  module Transport
    module Messages
      class Task < Legion::Transport::Message
        def exchange
          if @options.key?(:exchange) && @options[:exchange].is_a?(String)
            Legion::Transport::Exchanges.new(@options[:exchange])
          else
            Legion::Transport::Exchanges::Task.new
          end
        end

        def message
          @options
        end

        def routing_key # rubocop:disable Metrics/AbcSize
          if @options.key? :routing_key
            @options[:routing_key]
          elsif @options[:conditions].is_a?(String) && @options[:conditions].length > 2
            'task.subtask.conditioner'
          elsif @options[:transformation].is_a?(String) && @options[:transformation].length > 2
            'task.subtask.transform'
          elsif @options[:queue].is_a?(String) && @options[:function].is_a?(String)
            "#{@options[:queue]}.#{@options[:function]}"
          elsif @options[:queue].is_a?(String) && @options[:function_name].is_a?(String)
            "#{@options[:queue]}.#{@options[:function_name]}"
          elsif @options[:queue].is_a?(String) && @options[:name].is_a?(String)
            "#{@options[:queue]}.#{@options[:name]}"
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
