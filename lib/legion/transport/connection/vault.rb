# frozen_string_literal: true

require 'legion/logging/helper'
require 'tempfile'

module Legion
  module Transport
    module Connection
      module Vault
        include Legion::Logging::Helper

        # Provides Vault PKI-based cert issuance for Bunny mTLS connections.
        # Activated when `transport.tls.vault_pki: true` AND `Legion::Crypt::Mtls.enabled?`.
        # Bunny requires file paths for TLS material, so we write to tempfiles (auto-deleted
        # by the OS when the process exits — or call cleanup_pki_tempfiles explicitly).

        def vault_pki_tls_options
          return {} unless vault_pki_enabled?
          return {} unless defined?(Legion::Crypt::Mtls)
          return {} unless Legion::Crypt::Mtls.enabled?

          node_name = pki_node_name
          cert_data = Legion::Crypt::Mtls.issue_cert(common_name: node_name)
          Legion::Transport.logger.info(
            "[mTLS] Issued PKI cert for #{node_name}: serial=#{cert_data[:serial]} expiry=#{cert_data[:expiry]}"
          )

          build_bunny_tls_opts(cert_data)
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: 'transport.connection.vault_pki_tls_options')
          {}
        end

        def vault_pki_enabled?
          tls = transport_tls_settings
          return false unless tls.is_a?(Hash)

          tls[:vault_pki] || tls['vault_pki'] || false
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: 'transport.connection.vault_pki_enabled')
          false
        end

        private

        def build_bunny_tls_opts(cert_data)
          cert_file = write_pki_tempfile('legion-cert-', '.pem', cert_data[:cert])
          key_file  = write_pki_tempfile('legion-key-',  '.pem', cert_data[:key])
          ca_files  = Array(cert_data[:ca_chain]).map.with_index do |pem, i|
            write_pki_tempfile("legion-ca-#{i}-", '.pem', pem)
          end

          track_pki_tempfiles([cert_file, key_file] + ca_files)

          {
            tls:                 true,
            tls_cert:            cert_file,
            tls_key:             key_file,
            tls_ca_certificates: ca_files,
            verify_peer:         true
          }
        end

        def write_pki_tempfile(prefix, suffix, content)
          f = Tempfile.new([prefix, suffix])
          f.write(content)
          f.flush
          f.close
          f.path
        end

        def track_pki_tempfiles(paths)
          @pki_tempfiles ||= []
          @pki_tempfiles.concat(paths)
        end

        def pki_node_name
          return 'legion.internal' unless defined?(Legion::Settings)

          name = Legion::Settings[:client]&.dig(:name) || Legion::Settings[:client]&.dig('name')
          name || 'legion.internal'
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: 'transport.connection.pki_node_name')
          'legion.internal'
        end

        def transport_tls_settings
          return {} unless defined?(Legion::Settings)

          tls = Legion::Settings[:transport][:tls]
          tls.is_a?(Hash) ? tls : {}
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: 'transport.connection.transport_tls_settings')
          {}
        end
      end
    end
  end
end
