# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/transport/connection/vault'

RSpec.describe Legion::Transport::Connection::Vault do
  let(:test_obj) { Object.new.extend(described_class) }

  let(:cert_data) do
    {
      cert:     "-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----",
      key:      "-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n-----END RSA PRIVATE KEY-----",
      ca_chain: ["-----BEGIN CERTIFICATE-----\nCACA...\n-----END CERTIFICATE-----"],
      serial:   '01:02',
      expiry:   Time.now + 86_400
    }
  end

  describe '#vault_pki_tls_options' do
    context 'when vault_pki is disabled in settings' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          { tls: { vault_pki: false } }
        )
      end

      it 'returns empty hash' do
        expect(test_obj.vault_pki_tls_options).to eq({})
      end
    end

    context 'when vault_pki is enabled but Crypt::Mtls is not defined' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          { tls: { vault_pki: true } }
        )
        hide_const('Legion::Crypt::Mtls') if defined?(Legion::Crypt::Mtls)
      end

      it 'returns empty hash' do
        expect(test_obj.vault_pki_tls_options).to eq({})
      end
    end

    context 'when vault_pki is enabled but Mtls.enabled? is false' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          { tls: { vault_pki: true } }
        )
        mtls = Module.new
        stub_const('Legion::Crypt::Mtls', mtls)
        allow(Legion::Crypt::Mtls).to receive(:enabled?).and_return(false)
      end

      it 'returns empty hash' do
        expect(test_obj.vault_pki_tls_options).to eq({})
      end
    end

    context 'when vault_pki and Mtls.enabled? are both true' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          { tls: { vault_pki: true }, connection: { host: '127.0.0.1' } }
        )
        allow(Legion::Settings).to receive(:[]).with(:client).and_return({ name: 'test-node' })
        mtls = Module.new
        stub_const('Legion::Crypt::Mtls', mtls)
        allow(Legion::Crypt::Mtls).to receive(:enabled?).and_return(true)
        allow(Legion::Crypt::Mtls).to receive(:issue_cert).and_return(cert_data)
      end

      it 'calls Mtls.issue_cert with the node name' do
        expect(Legion::Crypt::Mtls).to receive(:issue_cert).with(
          common_name: 'test-node'
        ).and_return(cert_data)
        test_obj.vault_pki_tls_options
      end

      it 'returns a hash with tls: true' do
        opts = test_obj.vault_pki_tls_options
        expect(opts[:tls]).to be true
      end

      it 'returns verify_peer: true' do
        opts = test_obj.vault_pki_tls_options
        expect(opts[:verify_peer]).to be true
      end

      it 'returns tempfile paths for tls_cert and tls_key' do
        opts = test_obj.vault_pki_tls_options
        expect(opts[:tls_cert]).to be_a(String)
        expect(File.exist?(opts[:tls_cert])).to be true
        expect(opts[:tls_key]).to be_a(String)
        expect(File.exist?(opts[:tls_key])).to be true
      end

      it 'writes cert PEM content to the tempfile' do
        opts = test_obj.vault_pki_tls_options
        content = File.read(opts[:tls_cert])
        expect(content).to include('BEGIN CERTIFICATE')
      end

      it 'writes key PEM content to the tempfile' do
        opts = test_obj.vault_pki_tls_options
        content = File.read(opts[:tls_key])
        expect(content).to include('BEGIN RSA PRIVATE KEY')
      end

      it 'returns tls_ca_certificates as an array of tempfile paths' do
        opts = test_obj.vault_pki_tls_options
        expect(opts[:tls_ca_certificates]).to be_an(Array)
        expect(opts[:tls_ca_certificates]).not_to be_empty
      end
    end

    context 'when Mtls.issue_cert raises' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          { tls: { vault_pki: true }, connection: { host: '127.0.0.1' } }
        )
        allow(Legion::Settings).to receive(:[]).with(:client).and_return({ name: 'test-node' })
        mtls = Module.new
        stub_const('Legion::Crypt::Mtls', mtls)
        allow(Legion::Crypt::Mtls).to receive(:enabled?).and_return(true)
        allow(Legion::Crypt::Mtls).to receive(:issue_cert).and_raise(RuntimeError, 'Vault unreachable')
      end

      it 'returns empty hash and does not raise' do
        expect { test_obj.vault_pki_tls_options }.not_to raise_error
        expect(test_obj.vault_pki_tls_options).to eq({})
      end
    end
  end

  describe '#vault_pki_enabled?' do
    it 'returns false when transport.tls.vault_pki is false' do
      allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ tls: { vault_pki: false } })
      expect(test_obj.vault_pki_enabled?).to be false
    end

    it 'returns false when tls key is missing' do
      allow(Legion::Settings).to receive(:[]).with(:transport).and_return({})
      expect(test_obj.vault_pki_enabled?).to be false
    end

    it 'returns true when vault_pki is true' do
      allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ tls: { vault_pki: true } })
      expect(test_obj.vault_pki_enabled?).to be true
    end
  end
end
