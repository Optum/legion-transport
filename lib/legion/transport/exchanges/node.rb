module Legion
  module Transport
    module Exchanges
      class Node < Legion::Transport::Exchange
        def exchange_name
          'node'
        end
      end
    end
  end
end
