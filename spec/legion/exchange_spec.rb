require 'spec_helper'
require 'legion/settings'
Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
require 'legion/transport'
require 'legion/transport/connection'

RSpec.describe Legion::Transport::Exchange do
  it 'can init' do
    expect { Legion::Transport::Exchange.new('foobar') }.not_to raise_exception
  end

  it 'has default options' do
    expect(Legion::Transport::Exchange.new.exchange_name).to eq 'exchange'
    expect(Legion::Transport::Exchange.new.exchange_options).to eq({})
    expect(Legion::Transport::Exchange.new.default_type).to eq 'topic'
  end

  it 'does not throw error when deleting non existent exchange' do
    expect(Legion::Transport::Exchange.new('not_real').delete).to eq true
  end

  it 'can delete exchange' do
    expect(Legion::Transport::Exchange.new.delete_exchange('test')).to be_a AMQ::Protocol::Exchange::DeleteOk
  end

  # it 'will recreate an exchange' do
  #   expect { Legion::Transport::Exchange.new('foobar', type: 'direct') }.to raise_error ::Bunny::ChannelAlreadyClosed
  # end
end
