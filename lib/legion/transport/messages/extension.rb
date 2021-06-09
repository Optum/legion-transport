require 'legion/transport/exchanges/extensions'

module Legion
  module Transport
    module Messages
      class LexRegister < Legion::Transport::Message
        def exchange
          Legion::Transport::Exchanges::Extensions
        end

        def routing_key
          'extensions.register.'
        end

        def validate
          @valid = true
        end
      end
    end
  end
end
