# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Legion::Transport::Message, 'spool fallback' do
  let(:spool_dir) { Dir.mktmpdir('legion-spool') }

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
end
