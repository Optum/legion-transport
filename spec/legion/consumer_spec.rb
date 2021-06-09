require 'spec_helper'
require 'legion/settings'
Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
require 'legion/transport'
require 'legion/transport/connection'
require 'legion/transport/consumer'

RSpec.describe Legion::Transport::Consumer do
  it 'is a thing' do
    expect(Legion::Transport::Consumer).to be_a Class
    expect { Legion::Transport::Consumer.new(queue: 'test') }.not_to raise_exception
  end
end
