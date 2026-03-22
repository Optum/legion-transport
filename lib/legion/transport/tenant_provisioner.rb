# frozen_string_literal: true

require_relative 'tenant_topology'

module Legion
  module Transport
    module TenantProvisioner
      EXCHANGE_TYPES = %w[tasks results events].freeze

      def self.provision(tenant_id, channel: nil)
        ch = channel || Legion::Transport.connection.create_channel
        EXCHANGE_TYPES.each do |type|
          name = TenantTopology.exchange_name(type, tenant_id: tenant_id)
          ch.topic(name, durable: true)
        end
        dlx = TenantTopology.exchange_name('dlx', tenant_id: tenant_id)
        ch.fanout(dlx, durable: true)
        ch.close unless channel
        Legion::Logging.info "Provisioned tenant topology for tenant_id=#{tenant_id}" if defined?(Legion::Logging)
      rescue StandardError => e
        Legion::Logging.warn "Failed to provision tenant topology for tenant_id=#{tenant_id}: #{e.message}" if defined?(Legion::Logging)
        raise
      end

      def self.deprovision(tenant_id, channel: nil)
        ch = channel || Legion::Transport.connection.create_channel
        (EXCHANGE_TYPES + ['dlx']).each do |type|
          name = TenantTopology.exchange_name(type, tenant_id: tenant_id)
          begin
            ch.exchange_delete(name)
          rescue StandardError => e
            Legion::Logging.debug("TenantProvisioner#deprovision exchange delete failed for #{name}: #{e.message}") if defined?(Legion::Logging)
            nil
          end
        end
        ch.close unless channel
        Legion::Logging.info "Deprovisioned tenant topology for tenant_id=#{tenant_id}" if defined?(Legion::Logging)
      rescue StandardError => e
        Legion::Logging.warn "Failed to deprovision tenant topology for tenant_id=#{tenant_id}: #{e.message}" if defined?(Legion::Logging)
        raise
      end
    end
  end
end
