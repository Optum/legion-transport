# frozen_string_literal: true

module Legion
  module Transport
    module Connection
      module SSL
        def tls_options(tls_config: nil, port: nil)
          return {} unless defined?(Legion::Crypt::TLS)

          tls_config ||= tls_settings
          port       ||= transport_port

          tls = Legion::Crypt::TLS.resolve(tls_config, port: port)
          return {} unless tls[:enabled]

          {
            tls:                 true,
            tls_cert:            tls[:cert],
            tls_key:             tls[:key],
            tls_ca_certificates: [tls[:ca]].compact,
            verify_peer:         tls[:verify] != :none
          }
        end

        private

        def tls_settings
          return {} unless defined?(Legion::Settings)

          Legion::Settings[:transport][:tls] || {}
        rescue StandardError
          {}
        end

        def transport_port
          return nil unless defined?(Legion::Settings)

          Legion::Settings[:transport][:connection][:port]
        rescue StandardError
          nil
        end
      end
    end
  end
end
