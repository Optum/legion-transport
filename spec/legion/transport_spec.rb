require 'spec_helper'
require 'legion/transport'

RSpec.describe Legion::Transport do
  it 'has a version number' do
    expect(Legion::Transport::VERSION).not_to be nil
  end

  it 'has a connector' do
    expect(Legion::Transport::CONNECTOR).not_to be nil
    expect(Legion::Transport::CONNECTOR).to be ::Bunny
  end

  it 'has a type' do
    expect(Legion::Transport::TYPE).to eq 'bunny'
  end

  it 'has default settings' do
    expect(described_class.settings).to be_a Hash
  end
end
