require 'legion/settings'

module Legion
  module Transport
    module Settings
      def self.connection
        {
          read_timeout: 1,
          heartbeat: 30,
          automatically_recover: true,
          continuation_timeout: 4000,
          network_recovery_interval: 1,
          connection_timeout: 1,
          frame_max: 65_536,
          user: ENV['transport.connection.user'] || 'guest',
          password: ENV['transport.connection.password'] || 'guest',
          host: ENV['transport.connection.host'] || '127.0.0.1',
          port: ENV['transport.connection.port'] || '5672',
          vhost: ENV['transport.connection.vhost'] || '/',
          recovery_attempts: 100,
          logger_level: ENV['transport.log_level'] || 'info',
          connected: false
        }.merge(grab_vault_creds)
      end

      def self.grab_vault_creds
        return {} unless Legion::Settings[:crypt][:vault][:connected]

        Legion::Transport.logger.info 'Attempting to grab RabbitMQ creds from vault'
        lease = Legion::Crypt.read('rabbitmq/creds/legion', type: nil)
        Legion::Transport.logger.debug 'successfully grabbed amqp username from Vault'
        { user: lease[:username], password: lease[:password] }
      rescue StandardError
        Legion::Transport.logger.warn 'Error reading rabbitmq creds from vault'
        {}
      end

      def self.channel
        {
          default_worker_pool_size: ENV['transport.channel.default_worker_pool_size'] || 1,
          session_worker_pool_size: ENV['transport.channel.session_worker_pool_size'] || 8
        }
      end

      def self.queues
        {
          manual_ack: true,
          durable: true,
          exclusive: false,
          block: false,
          auto_delete: false,
          arguments: { 'x-max-priority': 255, 'x-overflow': 'reject-publish' }
        }
      end

      def self.exchanges
        {
          type: 'topic',
          arguments: {},
          auto_delete: false,
          durable: true,
          internal: false
        }
      end

      def self.messages
        {
          encrypt: ENV['transport.messsages.encrypt'] == 'true',
          ttl: ENV['transport.messages.ttl'],
          priority: ENV['transport.messages.priority'].to_i || 0,
          persistent: ENV['transport.messages.persistent'] == 'true'
        }
      end

      def self.default
        {
          type: 'rabbitmq',
          connected: false,
          logger_level: ENV['transport.logger_level'] || 'info',
          messages: messages,
          prefetch: ENV['transport.prefetch'].to_i || 2,
          exchanges: exchanges,
          queues: queues,
          connection: connection,
          channel: channel
        }
      end
    end
  end
end

begin
  Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default) if Legion.const_defined?('Settings')
rescue StandardError
  Legion::Transport.logger.fatal(e.message)
end
