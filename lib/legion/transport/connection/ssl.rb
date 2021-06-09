module Legion
  module Transport
    module Connection
      module SSL
        def settings
          Legion::Settings[:transport][:tls] || {}
        end

        def use_vault_pki?
          settings[:use_vault_pki] && Legion::Settings[:crypt][:vault][:connected]
        end

        def use_tls?
          settings[:use_tls] || Legion::Settings[:transport][:port] == 5671
        end

        def tls_cert
          settings[:tls_cert]
        end

        def tls_key
          settings[:tls_key]
        end

        def ca_certs
          settings[:ca_certs]
        end

        def verify_peer?
          settings[:verify_peer] || false
        end
      end
    end
  end
end
