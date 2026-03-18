# frozen_string_literal: true

module Legion
  module Transport
    module Exchanges
      class Agent < Legion::Transport::Exchange
        def exchange_name
          'agent'
        end
      end
    end
  end
end
