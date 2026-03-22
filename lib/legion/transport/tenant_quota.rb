# frozen_string_literal: true

require_relative 'tenant_topology'

module Legion
  module Transport
    module TenantQuota
      class QuotaExceededError < StandardError
      end

      WINDOW_SECONDS = 1

      @counters = {}
      @mutex = Mutex.new

      class << self
        def check_publish(tenant_id, message_size: 0)
          return true unless enabled?

          msg_limit  = rate_limit(tenant_id)
          size_limit = byte_limit(tenant_id)
          return true if msg_limit.nil? && size_limit.nil?

          now = current_window
          @mutex.synchronize do
            @counters[tenant_id] ||= { window: now, count: 0, bytes: 0 }
            entry = @counters[tenant_id]
            if entry[:window] != now
              entry[:window] = now
              entry[:count] = 0
              entry[:bytes] = 0
            end

            if msg_limit && entry[:count] >= msg_limit
              Legion::Logging.warn "Tenant #{tenant_id} exceeded message rate quota (#{msg_limit} msg/s)" if defined?(Legion::Logging)
              raise QuotaExceededError, "Tenant #{tenant_id} exceeded message rate quota (#{msg_limit} msg/s)"
            end

            if size_limit && (entry[:bytes] + message_size) > size_limit
              Legion::Logging.warn "Tenant #{tenant_id} exceeded byte rate quota (#{size_limit} bytes/s)" if defined?(Legion::Logging)
              raise QuotaExceededError, "Tenant #{tenant_id} exceeded byte rate quota (#{size_limit} bytes/s)"
            end

            entry[:count] += 1
            entry[:bytes] += message_size
          end
          true
        end

        def enabled?
          TenantTopology.enabled?
        end

        def reset!
          @mutex.synchronize { @counters.clear }
        end

        private

        def current_window
          (::Time.now.to_f / WINDOW_SECONDS).floor
        end

        def rate_limit(tenant_id)
          quota_settings(tenant_id)&.dig(:messages_per_second)
        end

        def byte_limit(tenant_id)
          quota_settings(tenant_id)&.dig(:bytes_per_second)
        end

        def quota_settings(tenant_id)
          return nil unless defined?(Legion::Settings)

          Legion::Settings.dig(:transport, :tenant_topology, :quotas, tenant_id.to_sym)
        rescue StandardError => e
          Legion::Logging.debug("TenantQuota#quota_settings failed for #{tenant_id}: #{e.message}") if defined?(Legion::Logging)
          nil
        end
      end
    end
  end
end
