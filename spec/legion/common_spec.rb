require 'spec_helper'
require 'legion/settings'
Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
require 'legion/transport'
require 'legion/transport/common'
require 'securerandom'

RSpec.describe Legion::Transport::Common do
  it 'should work' do
    @common = Kernel.const_set('Test', Class.new)
    @common.extend Legion::Transport::Common
    @common.include Legion::Transport::Common
    expect(@common.generate_consumer_tag(lex_name: 'lex', runner_name: 'runner', thread: 'thread')).to be_a String
    expect(@common.options_builder({ foo: 'bar' }, { hello: 'world' })).to eq({ foo: 'bar', hello: 'world' })
    expect(@common.deep_merge(
             { foo: { baz: 'bar' } },
             { foo: { hello: 'world', baz: 'other' } }
           )).to eq({ foo: { baz: 'other', hello: 'world' } })
    Legion::Transport::Connection.setup
    expect(@common.channel).to be_a ::Bunny::Channel
    expect(@common.channel_open?).to eq true

    # expect { @common.close }.not_to raise_exception
    # expect { @common.close! }.not_to raise_exception
  end
end
