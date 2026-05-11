# frozen_string_literal: true

require 'legion/logging/helper'
require_relative 'tenant_topology'

module Legion
  module Transport
    module TenantQuota
      extend Legion::Logging::Helper

      class QuotaExceededError < StandardError
      end

      WINDOW_SECONDS = 1
      STALE_SECONDS  = 300

      @counters      = {}
      @mutexes       = {}
      @registry_mutex = Mutex.new

      class << self
        def check_publish(tenant_id, message_size: 0)
          return true unless enabled?

          msg_limit  = rate_limit(tenant_id)
          size_limit = byte_limit(tenant_id)
          return true if msg_limit.nil? && size_limit.nil?

          now = current_window

          tenant_mutex(tenant_id).synchronize do
            @counters[tenant_id] ||= { window: now, count: 0, bytes: 0, updated_at: now }
            entry = @counters[tenant_id]
            if entry[:window] != now
              entry[:window]     = now
              entry[:count]      = 0
              entry[:bytes]      = 0
              entry[:updated_at] = now
            end

            if msg_limit && entry[:count] >= msg_limit
              log.warn "Tenant #{tenant_id} exceeded message rate quota (#{msg_limit} msg/s)"
              raise QuotaExceededError, "Tenant #{tenant_id} exceeded message rate quota (#{msg_limit} msg/s)"
            end

            if size_limit && (entry[:bytes] + message_size) > size_limit
              log.warn "Tenant #{tenant_id} exceeded byte rate quota (#{size_limit} bytes/s)"
              raise QuotaExceededError, "Tenant #{tenant_id} exceeded byte rate quota (#{size_limit} bytes/s)"
            end

            entry[:count]      += 1
            entry[:bytes]      += message_size
            entry[:updated_at]  = now
          end

          sweep_stale!
          true
        end

        def enabled?
          TenantTopology.enabled?
        end

        def reset!
          @registry_mutex.synchronize do
            @counters.clear
            @mutexes.clear
          end
        end

        private

        def tenant_mutex(tenant_id)
          @registry_mutex.synchronize do
            @mutexes[tenant_id] ||= Mutex.new
          end
        end

        def sweep_stale!
          stale_cutoff = current_window - (STALE_SECONDS / WINDOW_SECONDS)

          stale_ids = @registry_mutex.synchronize do
            @counters.each_with_object([]) do |(tid, entry), ids|
              ids << tid if entry[:updated_at] && entry[:updated_at] < stale_cutoff
            end
          end

          stale_ids.each do |tid|
            @registry_mutex.synchronize do
              @counters.delete(tid)
              @mutexes.delete(tid)
            end
          end
        end

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
          Legion::Settings.dig(:transport, :tenant_topology, :quotas, tenant_id.to_sym)
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :tenant_quota_settings, tenant_id: tenant_id)
          nil
        end
      end
    end
  end
end
