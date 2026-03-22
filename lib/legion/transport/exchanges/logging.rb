# frozen_string_literal: true

module Legion
  module Transport
    module Exchanges
      class Logging < Legion::Transport::Exchange
        def exchange_name
          'legion.logging'
        end
      end
    end
  end
end
