# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/exchanges/extensions'

RSpec.describe Legion::Transport::Exchanges::Extensions do
  it 'is a class' do
    expect(described_class).to be_a Class
  end

  it 'inherits from Legion::Transport::Exchange' do
    expect(described_class.ancestors).to include(Legion::Transport::Exchange)
  end

  it 'is defined under Legion::Transport::Exchanges' do
    expect(described_class.name).to eq 'Legion::Transport::Exchanges::Extensions'
  end

  it 'returns the correct exchange name' do
    instance = described_class.allocate
    expect(instance.exchange_name).to eq 'extensions'
  end
end
