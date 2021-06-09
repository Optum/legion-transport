module Legion::Transport::Messages # rubocop:disable Style/ClassAndModuleChildren
  class Dynamic < Legion::Transport::Message
    attr_accessor :options

    def type
      'task'
    end

    def message
      { args: @options[:args] || @options,
        function: function.values[:name] }
    end

    def routing_key
      "#{function.runner.extension.values[:name]}.#{function.runner.values[:name]}.#{function.values[:name]}"
    end

    def exchange
      Legion::Transport::Exchange.new(function.runner.extension.values[:exchange])
    end

    def function
      @function ||= Legion::Data::Model::Function[@options[:function_id]]
    end
  end
end
