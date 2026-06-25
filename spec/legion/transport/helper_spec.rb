# frozen_string_literal: true

RSpec.describe Legion::Transport::Helper do
  let(:test_class) do
    Class.new do
      include Legion::Transport::Helper

      def full_path
        '/opt/legion/extensions/lex-test'
      end
    end
  end

  let(:custom_ttl_class) do
    Class.new do
      include Legion::Transport::Helper

      def transport_default_ttl
        300_000
      end
    end
  end

  subject { test_class.new }

  describe '#transport_default_ttl' do
    it 'returns nil by default (no expiration)' do
      allow(Legion::Settings).to receive(:dig).with(:transport, :messages, :ttl).and_return(nil)
      expect(subject.transport_default_ttl).to be_nil
    end

    it 'returns the settings value when configured' do
      allow(Legion::Settings).to receive(:dig).with(:transport, :messages, :ttl).and_return(60_000)
      expect(subject.transport_default_ttl).to eq(60_000)
    end

    it 'can be overridden by a LEX' do
      obj = custom_ttl_class.new
      expect(obj.transport_default_ttl).to eq(300_000)
    end
  end

  describe '#transport_connected?' do
    it 'returns true when transport is connected' do
      allow(Legion::Settings).to receive(:dig).with(:transport, :connected).and_return(true)
      expect(subject.transport_connected?).to be true
    end

    it 'returns false when transport is not connected' do
      allow(Legion::Settings).to receive(:dig).with(:transport, :connected).and_return(false)
      expect(subject.transport_connected?).to be false
    end

    it 'returns false when settings raises' do
      allow(Legion::Settings).to receive(:dig).and_raise(StandardError)
      expect(subject.transport_connected?).to be false
    end
  end

  describe '#transport_session_open?' do
    it 'delegates to Connection.session_open?' do
      allow(Legion::Transport::Connection).to receive(:session_open?).and_return(true)
      expect(subject.transport_session_open?).to be true
    end

    it 'returns false on error' do
      allow(Legion::Transport::Connection).to receive(:session_open?).and_raise(StandardError)
      expect(subject.transport_session_open?).to be false
    end
  end

  describe '#transport_channel_open?' do
    it 'delegates to Connection.channel_open?' do
      allow(Legion::Transport::Connection).to receive(:channel_open?).and_return(true)
      expect(subject.transport_channel_open?).to be true
    end

    it 'returns false on error' do
      allow(Legion::Transport::Connection).to receive(:channel_open?).and_raise(StandardError)
      expect(subject.transport_channel_open?).to be false
    end
  end

  describe '#transport_lite_mode?' do
    it 'delegates to Connection.lite_mode?' do
      allow(Legion::Transport::Connection).to receive(:lite_mode?).and_return(false)
      expect(subject.transport_lite_mode?).to be false
    end
  end

  describe '#transport_channel' do
    it 'delegates to Connection.channel' do
      channel = double('channel')
      allow(Legion::Transport::Connection).to receive(:channel).and_return(channel)
      expect(subject.transport_channel).to eq(channel)
    end
  end

  describe '#transport_spool_count' do
    it 'delegates to Spool.count' do
      allow(Legion::Transport::Spool).to receive(:count).and_return(42)
      expect(subject.transport_spool_count).to eq(42)
    end

    it 'returns 0 on error' do
      allow(Legion::Transport::Spool).to receive(:count).and_raise(StandardError)
      expect(subject.transport_spool_count).to eq(0)
    end
  end

  describe '#transport_publish' do
    let(:exchange_instance) { instance_double(Legion::Transport::Exchange) }
    let(:exchange_class) { class_double(Legion::Transport::Exchange, new: exchange_instance, cached_instance: exchange_instance) }

    before do
      allow(subject).to receive(:transport_connected?).and_return(true)
      allow(subject).to receive(:default_exchange).and_return(exchange_class)
      allow(exchange_instance).to receive(:publish)
    end

    it 'publishes JSON-encoded payload to the default exchange' do
      expect(exchange_instance).to receive(:publish).with(
        '{"foo":"bar"}',
        routing_key: 'test.run'
      )
      expect(subject.transport_publish(routing_key: 'test.run', payload: { foo: 'bar' })).to be true
    end

    it 'passes through string payloads without re-encoding' do
      expect(exchange_instance).to receive(:publish).with(
        'raw-string',
        routing_key: 'test.run'
      )
      subject.transport_publish(routing_key: 'test.run', payload: 'raw-string')
    end

    it 'applies explicit TTL as expiration string' do
      expect(exchange_instance).to receive(:publish).with(
        '{}',
        routing_key: 'test.run',
        expiration:  '60000'
      )
      subject.transport_publish(routing_key: 'test.run', ttl: 60_000)
    end

    it 'applies transport_default_ttl when no explicit TTL' do
      allow(subject).to receive(:transport_default_ttl).and_return(30_000)
      expect(exchange_instance).to receive(:publish).with(
        '{}',
        routing_key: 'test.run',
        expiration:  '30000'
      )
      subject.transport_publish(routing_key: 'test.run')
    end

    it 'omits expiration when TTL is nil' do
      allow(subject).to receive(:transport_default_ttl).and_return(nil)
      expect(exchange_instance).to receive(:publish).with(
        '{}',
        routing_key: 'test.run'
      )
      subject.transport_publish(routing_key: 'test.run')
    end

    it 'returns false when transport is not connected' do
      allow(subject).to receive(:transport_connected?).and_return(false)
      expect(subject.transport_publish(routing_key: 'test.run')).to be false
    end

    it 'returns false when publish raises' do
      allow(exchange_instance).to receive(:publish).and_raise(StandardError, 'connection closed')
      expect(subject.transport_publish(routing_key: 'test.run')).to be false
    end

    it 'treats explicit ttl: nil as no expiration (does not fall back to default TTL)' do
      allow(subject).to receive(:transport_default_ttl).and_return(30_000)
      expect(exchange_instance).to receive(:publish).with(
        '{}',
        routing_key: 'test.run'
      )
      subject.transport_publish(routing_key: 'test.run', ttl: nil)
    end

    it 'passes through an explicit expiration: without overwriting it' do
      allow(subject).to receive(:transport_default_ttl).and_return(30_000)
      expect(exchange_instance).to receive(:publish).with(
        '{}',
        routing_key: 'test.run',
        expiration:  '99999'
      )
      subject.transport_publish(routing_key: 'test.run', expiration: '99999')
    end

    it 'forwards extra options to exchange publish' do
      expect(exchange_instance).to receive(:publish).with(
        '{}',
        routing_key: 'test.run',
        persistent:  true,
        priority:    5
      )
      subject.transport_publish(routing_key: 'test.run', persistent: true, priority: 5)
    end
  end

  describe '#transport_path' do
    it 'returns the transport subdirectory path' do
      expect(subject.transport_path).to eq('/opt/legion/extensions/lex-test/transport')
    end

    it 'memoizes the result' do
      first = subject.transport_path
      expect(subject.transport_path).to equal(first)
    end
  end

  describe '#transport_class' do
    let(:lex_transport) { Module.new }
    let(:lex_class) do
      mod = Module.new
      mod.const_set(:Transport, lex_transport)
      mod
    end
    let(:wired_class) do
      lc = lex_class
      Class.new do
        include Legion::Transport::Helper

        define_method(:lex_class) { lc }
      end
    end

    it 'returns the transport module for the lex class' do
      expect(wired_class.new.transport_class).to eq(lex_transport)
    end
  end
end
