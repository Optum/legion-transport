# frozen_string_literal: true

require 'legion/transport/version'
require 'legion/settings'
require 'legion/transport/settings'
require_relative 'transport/errors'

module Legion
  module Transport
    require 'bunny'
    TYPE = 'bunny'
    CONNECTOR = ::Bunny

    class << self
      def logger
        return @logger unless @logger.nil?

        require 'logger'
        @logger = ::Logger.new($stdout)
        configured_level = begin
          Legion::Settings[:transport][:logger_level]
        rescue StandardError => e
          warn "Transport#logger level lookup failed: #{e.message}"
          'warn'
        end
        @logger.level = case configured_level.to_s
                        when 'debug' then ::Logger::DEBUG
                        when 'info'  then ::Logger::INFO
                        when 'error' then ::Logger::ERROR
                        when 'fatal' then ::Logger::FATAL
                        else              ::Logger::WARN
                        end
        @logger
      end

      def settings
        Legion::Settings[:transport] if Legion.const_defined? 'Settings'

        Legion::Transport::Settings.default
      end
    end
  end

  require_relative 'transport/helpers/pool'
  require_relative 'transport/helpers/channel_pool'
  require_relative 'transport/helpers/policy'
  require_relative 'transport/common'
  require_relative 'transport/queue'
  require_relative 'transport/exchange'
  require_relative 'transport/message'
  require_relative 'transport/spool'
  require_relative 'transport/tenant_topology'
  require_relative 'transport/tenant_provisioner'
  require_relative 'transport/tenant_quota'
  require_relative 'transport/helper'
end
