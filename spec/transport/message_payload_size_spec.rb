# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Transport::Message, 'payload size enforcement' do
  it 'defines PayloadTooLarge in the Legion::Transport namespace' do
    expect(Legion::Transport::PayloadTooLarge.ancestors).to include(StandardError)
  end

  it 'reports max_payload_bytes defaulting to 1MB' do
    expect(described_class.max_payload_bytes).to eq(1_048_576)
  end

  context 'when the payload exceeds the limit' do
    it 'raises PayloadTooLarge before any AMQP interaction' do
      msg = described_class.new(data: 'x' * 2_000_000)
      allow(described_class).to receive(:max_payload_bytes).and_return(100)

      expect { msg.publish }.to raise_error(
        Legion::Transport::PayloadTooLarge,
        /exceeds limit of 100 bytes/
      )
    end

    it 'includes actual size in the error message' do
      msg = described_class.new(data: 'x' * 200)
      allow(described_class).to receive(:max_payload_bytes).and_return(50)

      expect { msg.publish }.to raise_error(Legion::Transport::PayloadTooLarge, /bytes/)
    end
  end

  context 'when the payload is within the limit' do
    it 'does not raise PayloadTooLarge' do
      msg = described_class.new(function: 'test')
      exchange_mock = instance_double(Legion::Transport::Exchange)
      allow(msg).to receive(:exchange).and_return(exchange_mock)
      allow(exchange_mock).to receive(:respond_to?).with(:cached_instance).and_return(false)
      allow(exchange_mock).to receive(:respond_to?).with(:new).and_return(false)
      allow(exchange_mock).to receive(:respond_to?).with(:name).and_return(true)
      allow(exchange_mock).to receive(:name).and_return('task')
      allow(exchange_mock).to receive(:publish).and_return(true)
      allow(msg).to receive(:encode_message).and_return('{"function":"test"}')

      expect { msg.publish }.not_to raise_error
    end
  end
end
