module Legion
  module Transport
    module Exchanges
      class Task < Legion::Transport::Exchange
        def exchange_name
          'task'
        end
      end
    end
  end
end
