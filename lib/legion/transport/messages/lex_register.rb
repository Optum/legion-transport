require 'legion/transport/exchanges/extensions'

module Legion
  module Transport
    module Messages
      class LexRegister < Legion::Transport::Message
        def exchange
          Legion::Transport::Exchanges::Extensions
        end

        def routing_key
          'extension_manager.register.save'
        end

        def validate
          unless @options[:runner_namespace].is_a? String
            # raise "runner_namespace is a #{@options[:runner_namespace].class}"
          end
          unless @options[:extension_namespace].is_a? String
            # raise "extension_namespace is a #{@options[:extension_namespace].class}"
          end
          unless @options[:function].is_a?(String) || @options[:function].is_a?(Symbol)
            # raise "function is a #{@options[:function].class}"
          end

          @valid = true
        end
      end
    end
  end
end
