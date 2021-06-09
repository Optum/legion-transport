module Legion::Transport::Messages # rubocop:disable Style/ClassAndModuleChildren
  class RequestClusterSecret < Legion::Transport::Message
    def routing_key
      'node.crypt.push_cluster_secret'
    end

    def message
      { function: 'push_cluster_secret',
        node_name: Legion::Settings[:client][:name],
        queue_name: "node.#{Legion::Settings[:client][:name]}",
        runner_class: 'Legion::Extensions::Node::Runners::Crypt',
        # public_key: Base64.encode64(Legion::Crypt.public_key) }
        public_key: Legion::Crypt.public_key }
    end

    def exchange
      require 'legion/transport/exchanges/node'
      Legion::Transport::Exchanges::Node
    end

    def encrypt?
      false
    end

    def type
      'task'
    end

    def validate
      @valid = true
    end
  end
end
