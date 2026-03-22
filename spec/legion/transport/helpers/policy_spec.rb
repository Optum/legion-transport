# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/helpers/policy'

RSpec.describe Legion::Transport::Helpers::Policy do
  let(:settings) do
    {
      connection:          { host: '127.0.0.1', user: 'guest', password: 'guest', vhost: '/' },
      management_port:     15_672,
      quorum_queue_policy: {
        enabled:        true,
        pattern:        '^legion\\.',
        delivery_limit: 5
      }
    }
  end

  let(:http_instance) { instance_double(Net::HTTP) }
  let(:response_ok) { instance_double(Net::HTTPResponse, code: '204') }
  let(:response_not_found) { instance_double(Net::HTTPResponse, code: '404') }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http_instance)
    allow(http_instance).to receive(:open_timeout=)
    allow(http_instance).to receive(:read_timeout=)
    allow(http_instance).to receive(:request).and_return(response_ok)
  end

  describe '.apply_quorum_policy!' do
    it 'returns false when policy is not enabled' do
      disabled = settings.merge(quorum_queue_policy: { enabled: false })
      expect(described_class.apply_quorum_policy!(settings: disabled)).to eq false
    end

    it 'returns false when quorum_queue_policy is nil' do
      expect(described_class.apply_quorum_policy!(settings: settings.merge(quorum_queue_policy: nil))).to eq false
    end

    it 'makes an HTTP PUT to the management API when enabled' do
      expect(http_instance).to receive(:request).with(instance_of(Net::HTTP::Put)).and_return(response_ok)
      result = described_class.apply_quorum_policy!(settings: settings)
      expect(result).to eq true
    end

    it 'sends correct JSON body with pattern and delivery_limit' do
      expect(http_instance).to receive(:request) do |req|
        body = JSON.parse(req.body)
        expect(body['pattern']).to eq('^legion\\.')
        expect(body['definition']['x-delivery-limit']).to eq(5)
        response_ok
      end
      described_class.apply_quorum_policy!(settings: settings)
    end

    it 'uses basic auth with connection credentials' do
      expect(http_instance).to receive(:request) do |req|
        expect(req['authorization']).not_to be_nil
        response_ok
      end
      described_class.apply_quorum_policy!(settings: settings)
    end

    it 'returns false and does not raise when API is unreachable' do
      allow(http_instance).to receive(:request).and_raise(Errno::ECONNREFUSED)
      allow(Legion::Transport.logger).to receive(:warn)
      result = described_class.apply_quorum_policy!(settings: settings)
      expect(result).to eq false
    end

    it 'logs warning when API call fails' do
      allow(http_instance).to receive(:request).and_raise(Errno::ECONNREFUSED)
      allow(Legion::Transport.logger).to receive(:warn)
      described_class.apply_quorum_policy!(settings: settings)
      expect(Legion::Transport.logger).to have_received(:warn).with(/Quorum policy apply failed/)
    end

    it 'returns false on HTTP 404' do
      allow(http_instance).to receive(:request).and_return(response_not_found)
      result = described_class.apply_quorum_policy!(settings: settings)
      expect(result).to eq false
    end

    it 'uses custom management port from settings' do
      custom = settings.merge(management_port: 25_672)
      expect(Net::HTTP).to receive(:new).with('127.0.0.1', 25_672).and_return(http_instance)
      described_class.apply_quorum_policy!(settings: custom)
    end

    it 'encodes vhost in the URL path' do
      custom = settings.dup
      custom[:connection] = custom[:connection].merge(vhost: '/my-vhost')
      expect(http_instance).to receive(:request) do |req|
        expect(req.path).to include('%2Fmy-vhost')
        response_ok
      end
      described_class.apply_quorum_policy!(settings: custom)
    end

    it 'uses custom pattern from settings' do
      custom = settings.dup
      custom[:quorum_queue_policy] = custom[:quorum_queue_policy].merge(pattern: '^app\\.')
      expect(http_instance).to receive(:request) do |req|
        body = JSON.parse(req.body)
        expect(body['pattern']).to eq('^app\\.')
        response_ok
      end
      described_class.apply_quorum_policy!(settings: custom)
    end
  end
end
