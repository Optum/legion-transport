# frozen_string_literal: true

require 'legion/transport/version'
require 'legion/settings'
require 'legion/transport/settings'

module Legion
  module Transport
    require 'bunny'
    TYPE = 'bunny'
    CONNECTOR = ::Bunny

    class << self
      def logger
        return @logger unless @logger.nil?

        @logger = if ::Legion.const_defined?('Logging')
                    ::Legion::Logging
                  else
                    require 'logger'
                    l = ::Logger.new($stdout)
                    l.level = Logger::ERROR
                    l
                  end
      end

      def settings
        return Legion::Settings[:transport] if Legion.const_defined? 'Settings'

        Legion::Transport::Settings.default
      end
    end
  end

  require_relative 'transport/common'
  require_relative 'transport/queue'
  require_relative 'transport/exchange'
  require_relative 'transport/message'
end
