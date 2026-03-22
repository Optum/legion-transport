# frozen_string_literal: true

module Legion
  module Transport
    module Queues
      module RegionOutbound
        module_function

        def declare_all
          peers = defined?(Legion::Settings) && Legion::Settings.dig(:region, :peers)
          return [] unless peers.is_a?(Array) && !peers.empty?

          current = defined?(Legion::Region) ? Legion::Region.current : nil
          peers.reject { |p| p == current }.map do |peer|
            declare_outbound(peer)
          end
        end

        def declare_outbound(target_region)
          queue_name = queue_name_for(target_region)
          channel = Legion::Transport::Connection.channel
          channel.queue(
            queue_name,
            durable:   true,
            arguments: { 'x-dead-letter-exchange' => 'tasks.dlx' }
          )
        rescue StandardError => e
          Legion::Transport.logger.warn "RegionOutbound: failed to declare queue for #{target_region}: #{e.message}"
          nil
        end

        def queue_name_for(target_region)
          "legion.tasks.outbound.#{target_region}"
        end
      end
    end
  end
end
