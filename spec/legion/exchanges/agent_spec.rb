# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/exchanges/agent'

RSpec.describe Legion::Transport::Exchanges::Agent do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Exchange' do
    expect(described_class.ancestors).to include(Legion::Transport::Exchange)
  end

  it 'is defined under Legion::Transport::Exchanges' do
    expect(described_class.name).to eq 'Legion::Transport::Exchanges::Agent'
  end

  it 'returns the correct exchange name' do
    instance = described_class.allocate
    expect(instance.exchange_name).to eq 'agent'
  end
end
