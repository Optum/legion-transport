# frozen_string_literal: true

require 'legion/logging/helper'
require_relative 'tenant_topology'

module Legion
  module Transport
    module TenantProvisioner
      extend Legion::Logging::Helper

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
        log.info "Provisioned tenant topology for tenant_id=#{tenant_id}"
      rescue StandardError => e
        handle_exception(e, level: :warn, handled: false, operation: 'transport.tenant_provisioner.provision',
                         tenant_id: tenant_id)
        raise
      end

      def self.deprovision(tenant_id, channel: nil)
        ch = channel || Legion::Transport.connection.create_channel
        (EXCHANGE_TYPES + ['dlx']).each do |type|
          name = TenantTopology.exchange_name(type, tenant_id: tenant_id)
          begin
            ch.exchange_delete(name)
          rescue StandardError => e
            handle_exception(e, level: :warn, handled: true, operation: 'transport.tenant_provisioner.deprovision_exchange',
                             tenant_id: tenant_id, exchange_name: name)
            nil
          end
        end
        ch.close unless channel
        log.info "Deprovisioned tenant topology for tenant_id=#{tenant_id}"
      rescue StandardError => e
        handle_exception(e, level: :warn, handled: false, operation: 'transport.tenant_provisioner.deprovision',
                         tenant_id: tenant_id)
        raise
      end
    end
  end
end
