# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/connection/ssl'

RSpec.describe Legion::Transport::Connection::SSL do
  let(:test_obj) { Object.new.extend(described_class) }

  describe '#tls_options via Legion::Crypt::TLS' do
    before do
      stub_const('Legion::Crypt::TLS', Module.new)
    end

    context 'when TLS is disabled' do
      it 'returns empty hash' do
        allow(Legion::Crypt::TLS).to receive(:resolve).and_return(
          { enabled: false, verify: :peer, ca: nil, cert: nil, key: nil, auto_detected: false }
        )
        expect(test_obj.tls_options).to eq({})
      end
    end

    context 'when TLS is enabled with peer verification' do
      it 'returns Bunny TLS options' do
        allow(Legion::Crypt::TLS).to receive(:resolve).and_return(
          { enabled: true, verify: :peer, ca: '/etc/ca.crt', cert: nil, key: nil, auto_detected: false }
        )
        opts = test_obj.tls_options
        expect(opts[:tls]).to be true
        expect(opts[:tls_ca_certificates]).to eq(['/etc/ca.crt'])
        expect(opts[:verify_peer]).to be true
        expect(opts[:tls_cert]).to be_nil
        expect(opts[:tls_key]).to be_nil
      end
    end

    context 'when TLS is enabled with verify none' do
      it 'sets verify_peer to false' do
        allow(Legion::Crypt::TLS).to receive(:resolve).and_return(
          { enabled: true, verify: :none, ca: nil, cert: nil, key: nil, auto_detected: false }
        )
        opts = test_obj.tls_options
        expect(opts[:tls]).to be true
        expect(opts[:verify_peer]).to be false
      end
    end

    context 'when TLS is enabled with mutual' do
      it 'includes cert and key' do
        allow(Legion::Crypt::TLS).to receive(:resolve).and_return(
          { enabled: true, verify: :mutual, ca: '/ca.crt', cert: '/c.crt', key: '/c.key', auto_detected: false }
        )
        opts = test_obj.tls_options
        expect(opts[:tls_cert]).to eq '/c.crt'
        expect(opts[:tls_key]).to eq '/c.key'
        expect(opts[:verify_peer]).to be true
      end
    end

    context 'when Legion::Crypt::TLS is not defined' do
      it 'returns empty hash' do
        hide_const('Legion::Crypt::TLS')
        expect(test_obj.tls_options).to eq({})
      end
    end
  end

  describe '#tls_options via direct settings (no Legion::Crypt::TLS)' do
    before { hide_const('Legion::Crypt::TLS') if defined?(Legion::Crypt::TLS) }

    context 'when tls is false in settings' do
      it 'returns empty hash' do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ tls: false })
        expect(test_obj.tls_options).to eq({})
      end
    end

    context 'when tls is nil in settings' do
      it 'returns empty hash' do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ tls: nil })
        expect(test_obj.tls_options).to eq({})
      end
    end

    context 'when tls is true with only ca cert' do
      it 'includes tls options with only ca cert' do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          { tls: true, tls_ca_cert: '/path/to/ca.pem', tls_client_cert: nil, tls_client_key: nil }
        )
        opts = test_obj.tls_options
        expect(opts[:tls]).to be true
        expect(opts[:tls_ca_certificates]).to eq(['/path/to/ca.pem'])
        expect(opts[:tls_cert]).to be_nil
        expect(opts[:tls_key]).to be_nil
      end
    end

    context 'when tls is true with full mTLS config' do
      it 'includes all TLS options' do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          {
            tls:             true,
            tls_ca_cert:     '/path/to/ca.pem',
            tls_client_cert: '/path/to/client.pem',
            tls_client_key:  '/path/to/client.key',
            verify_peer:     true
          }
        )
        opts = test_obj.tls_options
        expect(opts[:tls]).to be true
        expect(opts[:tls_ca_certificates]).to eq(['/path/to/ca.pem'])
        expect(opts[:tls_cert]).to eq('/path/to/client.pem')
        expect(opts[:tls_key]).to eq('/path/to/client.key')
        expect(opts[:verify_peer]).to be true
      end
    end

    context 'when verify_peer is not set' do
      it 'defaults verify_peer to true' do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          { tls: true, tls_ca_cert: '/path/to/ca.pem' }
        )
        opts = test_obj.tls_options
        expect(opts[:verify_peer]).to be true
      end
    end

    context 'when verify_peer is explicitly false' do
      it 'sets verify_peer to false' do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          { tls: true, tls_ca_cert: '/path/to/ca.pem', verify_peer: false }
        )
        opts = test_obj.tls_options
        expect(opts[:verify_peer]).to be false
      end
    end

    context 'when no cert paths are provided' do
      it 'returns tls options with empty ca_certificates array' do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ tls: true })
        opts = test_obj.tls_options
        expect(opts[:tls]).to be true
        expect(opts[:tls_ca_certificates]).to eq([])
        expect(opts[:tls_cert]).to be_nil
        expect(opts[:tls_key]).to be_nil
      end
    end
  end
end
