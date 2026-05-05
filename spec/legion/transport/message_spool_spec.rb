# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Legion::Transport::Message, 'spool fallback' do
  let(:spool_dir) { Dir.mktmpdir('legion-spool') }

  # Scoped test doubles — defined inside the example group to avoid constant leaks
  let(:return_info_class) { Struct.new(:reply_code, :reply_text, keyword_init: true) }
  let(:return_properties_class) { Struct.new(:correlation_id, :message_id, keyword_init: true) }

  let(:make_channel) do
    ri_class = return_info_class
    rp_class = return_properties_class
    Class.new do
      attr_reader :wait_timeout

      define_method(:initialize) do |confirm_result: true|
        @confirm_result = confirm_result
        @ri_class = ri_class
        @rp_class = rp_class
      end

      def confirm_select
        @confirm_selected = true
      end

      def confirm_selected?
        @confirm_selected == true
      end

      def wait_for_confirms(timeout = nil)
        @wait_timeout = timeout
        @confirm_result
      end

      def on_return(&block)
        @return_handler = block
      end

      def return_message(correlation_id:, message_id:)
        @return_handler.call(
          @ri_class.new(reply_code: 312, reply_text: 'NO_ROUTE'),
          @rp_class.new(correlation_id: correlation_id, message_id: message_id),
          '{}'
        )
      end
    end
  end

  let(:make_exchange) do
    Class.new do
      attr_reader :published_options, :channel

      def initialize(channel:, raise_error: nil, force_return: false)
        @channel = channel
        @raise_error = raise_error
        @force_return = force_return
      end

      def name
        'task'
      end

      def publish(_payload, **options)
        @published_options = options
        raise @raise_error if @raise_error

        channel.return_message(correlation_id: options[:correlation_id], message_id: options[:message_id]) if @force_return
        true
      end
    end
  end

  before do
    Legion::Transport::Spool.reset!
    Legion::Transport::Spool.setup(directory: spool_dir)
  end

  after { FileUtils.rm_rf(spool_dir) }

  it 'spools the message when exchange publish raises connection error' do
    msg = described_class.new(routing_key: 'test.run', function: 'test')
    exchange_mock = instance_double(Legion::Transport::Exchange)
    allow(msg).to receive(:exchange).and_return(exchange_mock)
    allow(exchange_mock).to receive(:respond_to?).with(:cached_instance).and_return(false)
    allow(exchange_mock).to receive(:respond_to?).with(:new).and_return(false)
    allow(exchange_mock).to receive(:respond_to?).with(:name).and_return(true)
    allow(exchange_mock).to receive(:name).and_return('task')
    allow(exchange_mock).to receive(:publish).and_raise(Bunny::ConnectionClosedError.new('closed'))
    allow(msg).to receive(:encode_message).and_return('{"test":true}')

    expect { msg.publish }.not_to raise_error
    expect(Legion::Transport::Spool.count).to eq(1)
  end

  it 'passes mandatory publish options and waits for publisher confirms' do
    channel = make_channel.new
    exchange = make_exchange.new(channel: channel)
    msg = described_class.new(routing_key: 'test.run', function: 'test', correlation_id: 'corr-1')
    allow(msg).to receive(:exchange).and_return(exchange)
    allow(msg).to receive(:encode_message).and_return('{"test":true}')

    result = msg.publish(mandatory: true, publisher_confirm: true, publish_confirm_timeout_ms: 500, spool: false)

    expect(result[:status]).to eq(:accepted)
    expect(result[:accepted]).to eq(true)
    expect(exchange.published_options[:mandatory]).to eq(true)
    expect(channel).to be_confirm_selected
    expect(channel.wait_timeout).to eq(0.5)
  end

  it 'returns unroutable when mandatory publish is returned by the broker' do
    channel = make_channel.new
    exchange = make_exchange.new(channel: channel, force_return: true)
    msg = described_class.new(routing_key: 'test.missing', function: 'test', correlation_id: 'corr-2')
    allow(msg).to receive(:exchange).and_return(exchange)
    allow(msg).to receive(:encode_message).and_return('{"test":true}')

    result = msg.publish(mandatory: true, publisher_confirm: true, spool: false)

    expect(result[:status]).to eq(:unroutable)
    expect(result[:accepted]).to eq(false)
    expect(result[:return_reply_code]).to eq(312)
    expect(result[:return_reply_text]).to eq('NO_ROUTE')
  end

  it 'does not spool when publish opts out of spool fallback' do
    error = Bunny::ConnectionClosedError.new('closed')
    channel = make_channel.new
    exchange = make_exchange.new(channel: channel, raise_error: error)
    msg = described_class.new(routing_key: 'test.live', function: 'test', correlation_id: 'corr-3')
    allow(msg).to receive(:exchange).and_return(exchange)
    allow(msg).to receive(:encode_message).and_return('{"test":true}')

    result = msg.publish(mandatory: true, publisher_confirm: true, spool: false)

    expect(result[:status]).to eq(:failed)
    expect(result[:accepted]).to eq(false)
    expect(Legion::Transport::Spool.count).to eq(0)
  end
end
