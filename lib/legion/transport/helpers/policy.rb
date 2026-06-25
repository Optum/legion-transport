# frozen_string_literal: true

require 'net/http'
require 'legion/logging/helper'

module Legion
  module Transport
    module Helpers
      module Policy
        extend Legion::Logging::Helper

        module_function

        def apply_quorum_policy!(settings: nil)
          settings ||= Legion::Settings[:transport]
          policy = settings[:quorum_queue_policy]
          return false unless policy && policy[:enabled]

          conn = settings[:connection]
          host = conn[:host] || '127.0.0.1'
          port = settings[:management_port] || 15_672
          user = conn[:user] || 'guest'
          pass = conn[:password] || 'guest'
          vhost = conn[:vhost] || '/'

          encoded_vhost = URI.encode_www_form_component(vhost)
          uri = URI("http://#{host}:#{port}/api/policies/#{encoded_vhost}/legion-quorum")

          body = {
            pattern:    policy[:pattern] || '^legion\\.',
            definition: {
              'x-queue-type':     'quorum',
              'x-delivery-limit': policy[:delivery_limit] || 5
            },
            'apply-to': 'queues',
            priority:   0
          }

          req = Net::HTTP::Put.new(uri)
          req.basic_auth(user, pass)
          req.content_type = 'application/json'
          req.body = Legion::JSON.dump(body)

          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 5
          http.read_timeout = 5
          response = http.request(req)

          applied = response.code.start_with?('2')
          log.info("Quorum policy applied pattern=#{policy[:pattern] || '^legion\\.'} host=#{host}:#{port}") if applied
          applied
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: 'transport.policy.apply_quorum',
                           host: host, port: port, vhost: vhost)
          false
        end
      end
    end
  end
end
