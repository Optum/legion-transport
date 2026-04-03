# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Transport::Connection, 'cluster node rotation' do
  before do
    described_class.instance_variable_set(:@session, nil)
    described_class.instance_variable_set(:@channel_thread, Concurrent::ThreadLocalVar.new(nil))
  end

  describe '#build_bunny_opts with cluster_nodes' do
    it 'merges cluster_nodes into resolved hosts' do
      Legion::Settings[:transport][:cluster_nodes] = ['rmq2:5672', 'rmq3:5672']
      opts = described_class.send(:build_bunny_opts, connection_name: 'test')
      expect(opts[:hosts]).to be_a(Array)
      hosts = opts[:hosts].map { |h| "#{h[:host]}:#{h[:port]}" }
      expect(hosts).to include('rmq2', 'rmq3').or include('rmq2:5672', 'rmq3:5672')
      Legion::Settings[:transport][:cluster_nodes] = []
    end

    it 'returns single-host path when cluster_nodes is empty' do
      Legion::Settings[:transport][:cluster_nodes] = []
      opts = described_class.send(:build_bunny_opts, connection_name: 'test')
      expect(opts[:host]).to eq('127.0.0.1')
      expect(opts[:hosts]).to be_nil
    end

    it 'deduplicates hosts from both sources' do
      Legion::Settings[:transport][:cluster_nodes] = ['127.0.0.1:5672']
      opts = described_class.send(:build_bunny_opts, connection_name: 'test')
      expect(opts[:host]).to eq('127.0.0.1')
      expect(opts[:hosts]).to be_nil
      Legion::Settings[:transport][:cluster_nodes] = []
    end

    it 'normalizes a single host:port connection entry' do
      allow(Legion::Settings).to receive(:[]).and_call_original
      transport_settings = Legion::Settings[:transport].dup
      connection_settings = transport_settings[:connection].dup
      connection_settings[:host] = 'rmq.example:5671'
      connection_settings[:port] = 5672
      connection_settings[:resolved_hosts] = ['rmq.example:5671']
      transport_settings[:connection] = connection_settings
      transport_settings[:cluster_nodes] = []
      allow(Legion::Settings).to receive(:[]).with(:transport).and_return(transport_settings)

      opts = described_class.send(:build_bunny_opts, connection_name: 'test')

      expect(opts[:host]).to eq('rmq.example')
      expect(opts[:port]).to eq(5671)
      expect(opts[:hosts]).to be_nil
    end

    it 'includes all unique hosts when cluster_nodes adds new entries' do
      Legion::Settings[:transport][:cluster_nodes] = ['rmq2:5672']
      opts = described_class.send(:build_bunny_opts, connection_name: 'test')
      hosts = opts[:hosts].map { |h| h[:host] }
      expect(hosts).to include('127.0.0.1')
      expect(hosts).to include('rmq2')
      Legion::Settings[:transport][:cluster_nodes] = []
    end
  end
end

RSpec.describe Legion::Transport::Connection, 'failover' do
  before do
    described_class.instance_variable_set(:@session, nil)
    described_class.instance_variable_set(:@channel_thread, Concurrent::ThreadLocalVar.new(nil))
  end

  describe '#create_session_with_failover' do
    it 'returns a Bunny session on successful connection' do
      session = instance_double(Bunny::Session)
      allow(Bunny).to receive(:new).and_return(session)
      result = described_class.send(:create_session_with_failover, connection_name: 'test')
      expect(result).to eq session
    end

    it 'tries next host on TCPConnectionFailed' do
      Legion::Settings[:transport][:cluster_nodes] = ['rmq2:5672']
      instance_double(Bunny::Session)
      good_session = instance_double(Bunny::Session)

      call_count = 0
      allow(Bunny).to receive(:new) do
        call_count += 1
        raise Bunny::TCPConnectionFailed, 'Connection refused' if call_count == 1

        good_session
      end

      result = described_class.send(:create_session_with_failover, connection_name: 'test')
      expect(result).to eq good_session
      Legion::Settings[:transport][:cluster_nodes] = []
    end

    it 'raises ClusterUnavailable when all nodes fail' do
      allow(Bunny).to receive(:new).and_raise(Bunny::TCPConnectionFailed, 'refused')

      expect do
        described_class.send(:create_session_with_failover, connection_name: 'test')
      end.to raise_error(Legion::Transport::ClusterUnavailable)
    end

    it 'logs warnings for each failed attempt' do
      Legion::Settings[:transport][:cluster_nodes] = ['rmq2:5672']
      allow(Bunny).to receive(:new).and_raise(Bunny::TCPConnectionFailed, 'refused')
      allow(described_class).to receive(:handle_exception).and_call_original

      begin
        described_class.send(:create_session_with_failover, connection_name: 'test')
      rescue Legion::Transport::ClusterUnavailable
        nil
      end

      expect(described_class).to have_received(:handle_exception).at_least(:once).with(
        instance_of(Bunny::TCPConnectionFailed),
        hash_including(level: :warn, handled: true, operation: 'transport.connection.create_session')
      )
      Legion::Settings[:transport][:cluster_nodes] = []
    end
  end
end
