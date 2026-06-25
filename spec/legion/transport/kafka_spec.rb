# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/kafka'

# All rdkafka interaction is mocked — no broker required.
RSpec.describe Legion::Transport::Kafka do
  # ---------------------------------------------------------------------------
  # Helpers / shared doubles
  # ---------------------------------------------------------------------------
  let(:delivery_report) do
    instance_double('Rdkafka::Producer::DeliveryReport',
                    topic_name: 'test.topic',
                    partition:  0,
                    offset:     42)
  end

  let(:delivery_handle) do
    handle = instance_double('Rdkafka::Producer::DeliveryHandle')
    allow(handle).to receive(:wait).and_return(delivery_report)
    handle
  end

  let(:rdkafka_producer) do
    prod = instance_double('Rdkafka::Producer')
    allow(prod).to receive(:produce).and_return(delivery_handle)
    allow(prod).to receive(:close)
    prod
  end

  let(:raw_message) do
    instance_double('Rdkafka::Consumer::Message',
                    topic:     'test.topic',
                    partition: 0,
                    offset:    0,
                    key:       nil,
                    headers:   {},
                    timestamp: Time.now,
                    payload:   '{"event":"test"}')
  end

  let(:rdkafka_consumer) do
    consumer = instance_double('Rdkafka::Consumer')
    allow(consumer).to receive(:subscribe)
    allow(consumer).to receive(:poll).and_return(raw_message, nil)
    allow(consumer).to receive(:commit)
    allow(consumer).to receive(:close)
    consumer
  end

  let(:rdkafka_config) do
    cfg = instance_double('Rdkafka::Config')
    allow(cfg).to receive(:producer).and_return(rdkafka_producer)
    allow(cfg).to receive(:consumer).and_return(rdkafka_consumer)
    cfg
  end

  # Enable Kafka in settings and stub rdkafka require + Config.new for each example.
  before do
    Legion::Settings[:transport][:kafka] ||= {}
    Legion::Settings[:transport][:kafka][:enabled] = true
    Legion::Settings[:transport][:kafka][:brokers] = ['127.0.0.1:9092']

    # Stub rdkafka at the require level so the gem doesn't need to be installed.
    allow(Legion::Transport::Kafka).to receive(:require_rdkafka)
    stub_const('Rdkafka::Config', Class.new do
      def self.new(_cfg)
        # overridden per-example via allow_any_instance_of or instance_double
        instance_double('Rdkafka::Config')
      end
    end)
  end

  after do
    Legion::Transport::Kafka.reset!
    Legion::Transport::Kafka::Producer.instance_variable_set(:@producer, nil)
    Legion::Transport::Kafka::Producer.instance_variable_set(:@mutex, nil)
    Legion::Settings[:transport][:kafka][:enabled] = false
  end

  # ---------------------------------------------------------------------------
  # .enabled?
  # ---------------------------------------------------------------------------
  describe '.enabled?' do
    it 'returns true when enabled and rdkafka is available' do
      expect(described_class.enabled?).to be true
    end

    it 'returns false when disabled in settings' do
      Legion::Settings[:transport][:kafka][:enabled] = false
      expect(described_class.enabled?).to be false
    end

    it 'returns false when rdkafka gem is missing' do
      allow(described_class).to receive(:require_rdkafka)
        .and_raise(Legion::Transport::Kafka::UnavailableError)
      expect(described_class.enabled?).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # .brokers / .default_group
  # ---------------------------------------------------------------------------
  describe '.brokers' do
    it 'returns the configured broker list' do
      expect(described_class.brokers).to eq(['127.0.0.1:9092'])
    end
  end

  describe '.default_group' do
    it 'returns the configured consumer group' do
      Legion::Settings[:transport][:kafka][:consumer_group] = 'my-group'
      expect(described_class.default_group).to eq('my-group')
    end

    it 'defaults to "legion" when not configured' do
      Legion::Settings[:transport][:kafka].delete(:consumer_group)
      expect(described_class.default_group).to eq('legion')
    end
  end

  # ---------------------------------------------------------------------------
  # .kafka_settings fallback
  # ---------------------------------------------------------------------------
  describe '.kafka_settings' do
    it 'falls back to DEFAULTS when Settings raises' do
      original = Legion::Settings[:transport]
      call_count = 0
      allow(Legion::Settings).to receive(:[]) do |key|
        call_count += 1
        raise StandardError if key == :transport && call_count == 1

        original
      end
      result = described_class.kafka_settings
      # Returns DEFAULTS hash when Settings access fails
      expect(result[:enabled]).to be false
      expect(result).to have_key(:brokers)
      expect(result).to have_key(:producer)
    end
  end

  # ---------------------------------------------------------------------------
  # .publish (delegates to Producer)
  # ---------------------------------------------------------------------------
  describe '.publish' do
    before do
      allow(Rdkafka::Config).to receive(:new).and_return(rdkafka_config)
      allow(rdkafka_config).to receive(:producer).and_return(rdkafka_producer)
    end

    it 'raises DisabledError when Kafka is disabled' do
      Legion::Settings[:transport][:kafka][:enabled] = false
      expect { described_class.publish('topic', 'msg') }
        .to raise_error(Legion::Transport::Kafka::DisabledError)
    end

    it 'raises UnavailableError when rdkafka gem is missing' do
      allow(described_class).to receive(:require_rdkafka)
        .and_raise(Legion::Transport::Kafka::UnavailableError, 'not installed')
      expect { described_class.publish('topic', 'msg') }
        .to raise_error(Legion::Transport::Kafka::UnavailableError)
    end

    it 'delegates to Producer.publish and returns delivery metadata' do
      allow(Legion::Transport::Kafka::Producer).to receive(:publish)
        .with('test.topic', '{"x":1}', key: nil, headers: {}, partition: nil)
        .and_return({ topic: 'test.topic', partition: 0, offset: 42 })

      result = described_class.publish('test.topic', '{"x":1}')
      expect(result[:topic]).to eq('test.topic')
      expect(result[:offset]).to eq(42)
    end

    it 'forwards key and headers' do
      allow(Legion::Transport::Kafka::Producer).to receive(:publish)
        .with('t', 'val', key: 'k1', headers: { 'h' => 'v' }, partition: nil)
        .and_return({ topic: 't', partition: 0, offset: 1 })

      result = described_class.publish('t', 'val', key: 'k1', headers: { 'h' => 'v' })
      expect(result[:topic]).to eq('t')
    end

    it 'forwards explicit partition' do
      allow(Legion::Transport::Kafka::Producer).to receive(:publish)
        .with('t', 'val', key: nil, headers: {}, partition: 3)
        .and_return({ topic: 't', partition: 3, offset: 0 })

      result = described_class.publish('t', 'val', partition: 3)
      expect(result[:partition]).to eq(3)
    end
  end

  # ---------------------------------------------------------------------------
  # .subscribe (delegates to Consumer)
  # ---------------------------------------------------------------------------
  describe '.subscribe' do
    it 'raises DisabledError when Kafka is disabled' do
      Legion::Settings[:transport][:kafka][:enabled] = false
      expect { described_class.subscribe('topic') { |_m| nil } }
        .to raise_error(Legion::Transport::Kafka::DisabledError)
    end

    it 'delegates to Consumer.subscribe with defaults' do
      allow(Legion::Transport::Kafka::Consumer).to receive(:subscribe)
        .with('test.topic', group: 'legion', from_beginning: false, max_messages: nil)
        .and_yield(instance_double('Legion::Transport::Kafka::IncomingMessage'))

      received = []
      described_class.subscribe('test.topic', group: 'legion') { |m| received << m }
      expect(received.size).to eq(1)
    end

    it 'passes max_messages to Consumer' do
      allow(Legion::Transport::Kafka::Consumer).to receive(:subscribe)
        .with('t', group: 'g', from_beginning: true, max_messages: 5)

      described_class.subscribe('t', group: 'g', from_beginning: true, max_messages: 5) { |_m| nil }
    end
  end

  # ---------------------------------------------------------------------------
  # .replay (delegates to Consumer)
  # ---------------------------------------------------------------------------
  describe '.replay' do
    it 'raises DisabledError when Kafka is disabled' do
      Legion::Settings[:transport][:kafka][:enabled] = false
      expect { described_class.replay('topic') { |_m| nil } }
        .to raise_error(Legion::Transport::Kafka::DisabledError)
    end

    it 'delegates to Consumer.replay with from_beginning: true by default' do
      allow(Legion::Transport::Kafka::Consumer).to receive(:replay) do |topic, **opts, &_block|
        expect(topic).to eq('test.topic')
        expect(opts[:from_beginning]).to be true
      end

      described_class.replay('test.topic') { |_m| nil }
    end

    it 'passes from_offset when provided' do
      allow(Legion::Transport::Kafka::Consumer).to receive(:replay) do |_topic, **opts, &_block|
        expect(opts[:from_offset]).to eq(100)
      end

      described_class.replay('test.topic', from_offset: 100) { |_m| nil }
    end

    it 'passes from_timestamp when provided' do
      ts = Time.now
      allow(Legion::Transport::Kafka::Consumer).to receive(:replay) do |_topic, **opts, &_block|
        expect(opts[:from_timestamp]).to eq(ts)
      end

      described_class.replay('test.topic', from_timestamp: ts) { |_m| nil }
    end
  end

  # ---------------------------------------------------------------------------
  # .ensure_topic (delegates to Admin)
  # ---------------------------------------------------------------------------
  describe '.ensure_topic' do
    it 'raises DisabledError when Kafka is disabled' do
      Legion::Settings[:transport][:kafka][:enabled] = false
      expect { described_class.ensure_topic('topic') }
        .to raise_error(Legion::Transport::Kafka::DisabledError)
    end

    it 'delegates to Admin.ensure_topic' do
      allow(Legion::Transport::Kafka::Admin).to receive(:ensure_topic)
        .with('new.topic', partitions: 3, replication_factor: 2, config: {})
        .and_return(true)

      result = described_class.ensure_topic('new.topic', partitions: 3, replication_factor: 2)
      expect(result).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Error classes
  # ---------------------------------------------------------------------------
  describe 'error hierarchy' do
    it 'DisabledError is a StandardError' do
      expect(Legion::Transport::Kafka::DisabledError.ancestors).to include(StandardError)
    end

    it 'UnavailableError is a StandardError' do
      expect(Legion::Transport::Kafka::UnavailableError.ancestors).to include(StandardError)
    end

    it 'PublishError is a StandardError' do
      expect(Legion::Transport::Kafka::PublishError.ancestors).to include(StandardError)
    end

    it 'ConsumerError is a StandardError' do
      expect(Legion::Transport::Kafka::ConsumerError.ancestors).to include(StandardError)
    end

    it 'AdminError is a StandardError' do
      expect(Legion::Transport::Kafka::AdminError.ancestors).to include(StandardError)
    end
  end
end

# ---------------------------------------------------------------------------
# Producer unit tests (isolated from the top-level Kafka module)
# ---------------------------------------------------------------------------
RSpec.describe Legion::Transport::Kafka::Producer do
  let(:delivery_report) do
    instance_double('Rdkafka::Producer::DeliveryReport',
                    topic_name: 'test.topic',
                    partition:  0,
                    offset:     7)
  end

  let(:delivery_handle) do
    handle = instance_double('Rdkafka::Producer::DeliveryHandle')
    allow(handle).to receive(:wait).and_return(delivery_report)
    handle
  end

  let(:rdkafka_producer) do
    prod = instance_double('Rdkafka::Producer')
    allow(prod).to receive(:produce).and_return(delivery_handle)
    allow(prod).to receive(:close)
    prod
  end

  let(:rdkafka_config) do
    cfg = instance_double('Rdkafka::Config')
    allow(cfg).to receive(:producer).and_return(rdkafka_producer)
    cfg
  end

  before do
    Legion::Settings[:transport][:kafka] ||= {}
    Legion::Settings[:transport][:kafka][:enabled] = true
    Legion::Settings[:transport][:kafka][:brokers] = ['127.0.0.1:9092']

    # Stub the Rdkafka constant so specs don't need the native gem installed.
    stub_const('Rdkafka', Module.new)
    stub_const('Rdkafka::Config', Class.new)
    stub_const('Rdkafka::Producer', Class.new)
    stub_const('Rdkafka::Producer::DeliveryReport', Class.new)
    stub_const('Rdkafka::Producer::DeliveryHandle', Class.new)
    allow(Rdkafka::Config).to receive(:new).and_return(rdkafka_config)
    described_class.instance_variable_set(:@producer, nil)
    described_class.instance_variable_set(:@mutex, nil)
  end

  after do
    described_class.reset!
    described_class.instance_variable_set(:@producer, nil)
    described_class.instance_variable_set(:@mutex, nil)
    Legion::Settings[:transport][:kafka][:enabled] = false
  end

  describe '.publish' do
    it 'returns topic, partition, offset on success' do
      result = described_class.publish('test.topic', 'hello')
      expect(result).to eq({ topic: 'test.topic', partition: 0, offset: 7 })
    end

    it 'JSON-encodes Hash payloads' do
      expect(rdkafka_producer).to receive(:produce) do |**opts|
        expect(opts[:payload]).to include('"event"')
        delivery_handle
      end
      described_class.publish('test.topic', { event: 'login' })
    end

    it 'passes string payload unchanged' do
      expect(rdkafka_producer).to receive(:produce) do |**opts|
        expect(opts[:payload]).to eq('raw-string')
        delivery_handle
      end
      described_class.publish('test.topic', 'raw-string')
    end

    it 'omits key from produce opts when nil' do
      expect(rdkafka_producer).to receive(:produce) do |**opts|
        expect(opts).not_to have_key(:key)
        delivery_handle
      end
      described_class.publish('test.topic', 'msg', key: nil)
    end

    it 'includes key when provided' do
      expect(rdkafka_producer).to receive(:produce) do |**opts|
        expect(opts[:key]).to eq('mykey')
        delivery_handle
      end
      described_class.publish('test.topic', 'msg', key: 'mykey')
    end

    it 'includes explicit partition when provided' do
      expect(rdkafka_producer).to receive(:produce) do |**opts|
        expect(opts[:partition]).to eq(2)
        delivery_handle
      end
      described_class.publish('test.topic', 'msg', partition: 2)
    end

    it 'raises PublishError when rdkafka raises' do
      allow(rdkafka_producer).to receive(:produce).and_raise(StandardError, 'broker down')
      expect { described_class.publish('test.topic', 'msg') }
        .to raise_error(Legion::Transport::Kafka::PublishError, /broker down/)
    end

    it 'stringifies header keys and values' do
      expect(rdkafka_producer).to receive(:produce) do |**opts|
        expect(opts[:headers]).to eq({ 'source' => 'legion', 'version' => '2' })
        delivery_handle
      end
      described_class.publish('test.topic', 'msg', headers: { source: :legion, version: 2 })
    end
  end

  describe '.reset!' do
    it 'closes and clears the producer' do
      described_class.instance_variable_set(:@producer, rdkafka_producer)
      described_class.instance_variable_set(:@mutex, Mutex.new)
      expect(rdkafka_producer).to receive(:close)
      described_class.reset!
      expect(described_class.instance_variable_get(:@producer)).to be_nil
    end

    it 'is safe to call when no producer exists' do
      described_class.instance_variable_set(:@producer, nil)
      expect { described_class.reset! }.not_to raise_error
    end
  end
end

# ---------------------------------------------------------------------------
# IncomingMessage unit tests
# ---------------------------------------------------------------------------
RSpec.describe Legion::Transport::Kafka::IncomingMessage do
  let(:raw) do
    instance_double('Rdkafka::Consumer::Message',
                    topic:     'audit.events',
                    partition: 1,
                    offset:    99,
                    key:       'user-42',
                    headers:   { 'source' => 'legion' },
                    timestamp: Time.at(1_700_000_000),
                    payload:   '{"action":"login"}')
  end

  subject(:msg) { described_class.new(raw) }

  it 'exposes topic' do
    expect(msg.topic).to eq('audit.events')
  end

  it 'exposes partition' do
    expect(msg.partition).to eq(1)
  end

  it 'exposes offset' do
    expect(msg.offset).to eq(99)
  end

  it 'exposes key' do
    expect(msg.key).to eq('user-42')
  end

  it 'exposes headers' do
    expect(msg.headers).to eq({ 'source' => 'legion' })
  end

  it 'exposes timestamp' do
    expect(msg.timestamp).to eq(Time.at(1_700_000_000))
  end

  it 'returns raw payload string' do
    expect(msg.payload).to eq('{"action":"login"}')
  end

  it 'decoded_payload parses JSON' do
    stub_const('Legion::JSON', Module.new do
      def self.parse(str)
        require 'json'
        JSON.parse(str)
      end
    end)
    expect(msg.decoded_payload).to eq({ 'action' => 'login' })
  end

  it 'decoded_payload returns raw string on parse failure' do
    allow(raw).to receive(:payload).and_return('not-json{{{')
    bad_msg = described_class.new(raw)
    expect(bad_msg.decoded_payload).to eq('not-json{{{')
  end

  it 'to_s includes topic partition and offset' do
    expect(msg.to_s).to eq('audit.events[1]@99')
  end

  it 'inspect includes class name and key fields' do
    expect(msg.inspect).to include('IncomingMessage')
    expect(msg.inspect).to include('audit.events')
  end

  it 'raw returns the original rdkafka message' do
    expect(msg.raw).to be(raw)
  end

  context 'when headers is nil' do
    let(:raw_no_headers) do
      instance_double('Rdkafka::Consumer::Message',
                      topic: 't', partition: 0, offset: 0,
                      key: nil, headers: nil,
                      timestamp: Time.now, payload: 'x')
    end

    it 'defaults headers to empty hash' do
      expect(described_class.new(raw_no_headers).headers).to eq({})
    end
  end
end

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
RSpec.describe Legion::Transport::Kafka::DEFAULTS do
  it 'is disabled by default' do
    expect(described_class[:enabled]).to be false
  end

  it 'has a default broker' do
    expect(described_class[:brokers]).not_to be_empty
  end

  it 'has a default consumer group' do
    expect(described_class[:consumer_group]).not_to be_nil
  end

  it 'has producer defaults' do
    expect(described_class[:producer]).to be_a(Hash)
    expect(described_class[:producer]).to have_key(:acks)
    expect(described_class[:producer]).to have_key(:retries)
    expect(described_class[:producer]).to have_key(:compression)
  end

  it 'has consumer defaults' do
    expect(described_class[:consumer]).to be_a(Hash)
    expect(described_class[:consumer]).to have_key(:poll_timeout_ms)
    expect(described_class[:consumer]).to have_key(:auto_offset_reset)
  end

  it 'has admin defaults' do
    expect(described_class[:admin]).to be_a(Hash)
    expect(described_class[:admin]).to have_key(:operation_timeout_ms)
  end

  it 'has security defaults' do
    expect(described_class[:security]).to be_a(Hash)
    expect(described_class[:security][:protocol]).to eq('plaintext')
  end
end
