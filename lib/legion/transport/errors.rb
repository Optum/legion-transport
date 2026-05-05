# frozen_string_literal: true

module Legion
  module Transport
    class PoolTimeout < StandardError; end
    class ClusterUnavailable < StandardError; end
    class PayloadTooLarge < StandardError; end
  end
end

unless defined?(Bunny)
  module Bunny
    class ConnectionClosedError < StandardError; end
    class ChannelAlreadyClosed < StandardError; end
    class ChannelError < StandardError; end
    class NetworkErrorWrapper < StandardError; end
  end
end
