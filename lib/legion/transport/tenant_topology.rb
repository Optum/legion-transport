# frozen_string_literal: true

require 'legion/logging/helper'

module Legion
  module Transport
    module TenantTopology
      extend Legion::Logging::Helper

      SHARED_EXCHANGES = %w[legion.control legion.health legion.audit].freeze

      def self.exchange_name(base_name, tenant_id: nil)
        return base_name unless enabled?

        tid = tenant_id || current_tenant_id
        return base_name if tid.nil? || tid == 'default' || shared?(base_name)

        "t.#{tid}.#{base_name}"
      end

      def self.queue_name(base_name, tenant_id: nil)
        return base_name unless enabled?

        tid = tenant_id || current_tenant_id
        return base_name if tid.nil? || tid == 'default'

        "t.#{tid}.#{base_name}"
      end

      def self.shared?(name)
        SHARED_EXCHANGES.any? { |prefix| name.start_with?(prefix) }
      end

      def self.enabled?
        settings = transport_settings
        settings.is_a?(Hash) && settings.dig(:tenant_topology, :enabled) == true
      end

      def self.current_tenant_id
        return nil unless defined?(Legion::TenantContext)

        Legion::TenantContext.current_tenant_id
      rescue StandardError => e
        handle_exception(e, level: :warn, handled: true, operation: :tenant_topology_current_tenant_id)
        nil
      end

      private_class_method def self.transport_settings
        return {} unless defined?(Legion::Settings)

        Legion::Settings[:transport] || {}
      rescue StandardError => e
        handle_exception(e, level: :warn, handled: true, operation: :tenant_topology_transport_settings)
        {}
      end
    end
  end
end
