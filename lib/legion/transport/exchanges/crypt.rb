module Legion
  module Transport
    module Exchanges
      class Crypt < Legion::Transport::Exchange
        def exchange_name
          'crypt'
        end
      end
    end
  end
end
