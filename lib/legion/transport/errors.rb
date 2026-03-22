# frozen_string_literal: true

module Legion
  module Transport
    class PoolTimeout < StandardError; end
    class ClusterUnavailable < StandardError; end
  end
end
