require 'legion/transport/version'
require 'legion/settings'
require 'legion/transport/settings'

module Legion
  module Transport
    begin
      require 'march_hare'
      TYPE = 'march_hare'.freeze
      CONNECTOR = ::MarchHare
    rescue LoadError
      require 'bunny'
      TYPE = 'bunny'.freeze
      CONNECTOR = ::Bunny
    end

    class << self
      def logger
        @logger unless @logger.nil?

        if ::Legion.const_defined?('Logging')
          @logger = ::Legion::Logging
        else
          require 'logger'
          @logger = ::Logger.new($stdout)
          @logger.level = Logger::ERROR
        end

        @logger
      end

      def settings
        Legion::Settings[:transport] if Legion.const_defined? 'Settings'

        Legion::Transport::Settings.default
      end
    end
  end

  require_relative 'transport/common'
  require_relative 'transport/queue'
  require_relative 'transport/exchange'
  require_relative 'transport/message'
end
