module Legion
  module Transport
    module Exchanges
      class Extensions < Legion::Transport::Exchange
        def exchange_name
          'extensions'
        end
      end
    end
  end
end
