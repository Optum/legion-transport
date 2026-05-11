# frozen_string_literal: true

require 'legion/logging/helper'

module Legion
  module Transport
    module TenantTopology
      extend Legion::Logging::Helper

      DEFAULT_SHARED_EXCHANGES = %w[legion.control legion.health legion.audit].freeze
      DEFAULT_PREFIX_FORMAT = 't.%<tenant_id>s.%<name>s'

      def self.exchange_name(base_name, tenant_id: nil)
        return base_name unless enabled?

        tid = tenant_id || current_tenant_id
        return base_name if tid.nil? || tid == 'default' || shared?(base_name)

        format(prefix_format, tenant_id: tid, name: base_name)
      end

      def self.queue_name(base_name, tenant_id: nil)
        return base_name unless enabled?

        tid = tenant_id || current_tenant_id
        return base_name if tid.nil? || tid == 'default'

        format(prefix_format, tenant_id: tid, name: base_name)
      end

      def self.shared?(name)
        configured_shared_exchanges.any? do |entry|
          name == entry || name.start_with?("#{entry}.")
        end
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

      private_class_method def self.prefix_format
        settings = transport_settings
        return DEFAULT_PREFIX_FORMAT unless settings.is_a?(Hash)

        settings.dig(:tenant_topology, :prefix_format) || DEFAULT_PREFIX_FORMAT
      end

      private_class_method def self.configured_shared_exchanges
        settings = transport_settings
        return DEFAULT_SHARED_EXCHANGES unless settings.is_a?(Hash)

        Array(settings.dig(:tenant_topology, :shared_exchanges)).tap do |arr|
          return DEFAULT_SHARED_EXCHANGES if arr.empty?
        end
      end

      private_class_method def self.transport_settings
        Legion::Settings[:transport] || {}
      rescue StandardError => e
        handle_exception(e, level: :warn, handled: true, operation: :tenant_topology_transport_settings)
        {}
      end
    end
  end
end
