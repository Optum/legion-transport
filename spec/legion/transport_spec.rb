# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport'

RSpec.describe Legion::Transport do
  before do
    described_class.instance_variable_set(:@logger, nil)
  end

  it 'has a version number' do
    expect(Legion::Transport::VERSION).not_to be nil
  end

  it 'has a connector' do
    expect(Legion::Transport::CONNECTOR).not_to be nil
    if ENV['LEGION_MODE'] == 'lite'
      expect(Legion::Transport::CONNECTOR).to eq Legion::Transport::InProcess
    else
      expect(Legion::Transport::CONNECTOR).to be Bunny
    end
  end

  it 'has a type' do
    if ENV['LEGION_MODE'] == 'lite'
      expect(Legion::Transport::TYPE).to eq 'local'
    else
      expect(Legion::Transport::TYPE).to eq 'bunny'
    end
  end

  it 'has default settings' do
    expect(described_class.settings).to be_a Hash
  end

  it 'uses transport.log_level for the transport connector logger' do
    allow(described_class).to receive(:settings).and_return({ log_level: 'info' })

    expect(described_class.logger.level).to eq(Logger::INFO)
  end

  it 'supports legacy transport.logger_level for the transport connector logger' do
    allow(described_class).to receive(:settings).and_return({ logger_level: 'error' })

    expect(described_class.logger.level).to eq(Logger::ERROR)
  end
end
