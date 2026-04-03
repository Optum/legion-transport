# frozen_string_literal: true

require 'legion/logging/helper'

module Legion
  module Transport
    module Connection
      module SSL
        include Legion::Logging::Helper

        def tls_options(tls_config: nil, port: nil)
          if defined?(Legion::Crypt::TLS)
            tls_config ||= tls_settings
            port       ||= transport_port

            tls = Legion::Crypt::TLS.resolve(tls_config, port: port)
            return {} unless tls[:enabled]

            Legion::Transport.logger.info '[Transport] TLS enabled for RabbitMQ connection'
            return {
              tls:                 true,
              tls_cert:            tls[:cert],
              tls_key:             tls[:key],
              tls_ca_certificates: [tls[:ca]].compact,
              verify_peer:         tls[:verify] != :none
            }
          end

          direct_tls_options
        end

        private

        def direct_tls_options
          transport = defined?(Legion::Settings) ? Legion::Settings[:transport] : {}
          return {} unless transport[:tls]

          Legion::Transport.logger.info '[Transport] TLS enabled for RabbitMQ connection'

          {
            tls:                 true,
            tls_ca_certificates: [transport[:tls_ca_cert]].compact,
            tls_cert:            transport[:tls_client_cert],
            tls_key:             transport[:tls_client_key],
            verify_peer:         transport[:verify_peer] != false
          }
        end

        def tls_settings
          return {} unless defined?(Legion::Settings)

          Legion::Settings[:transport][:tls] || {}
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: 'transport.connection.ssl.tls_settings')
          {}
        end

        def transport_port
          return nil unless defined?(Legion::Settings)

          Legion::Settings[:transport][:connection][:port]
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: 'transport.connection.ssl.transport_port')
          nil
        end
      end
    end
  end
end
