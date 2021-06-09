require 'spec_helper'
require 'legion/transport/queue'

RSpec.describe Legion::Transport::Queue do
  it 'is a class' do
    expect(Legion::Transport::Queue).to be_a Class
  end

  let(:klass) { Legion::Transport::Queue }
  it 'can init' do
    expect { klass.new('test') }.not_to raise_error
    expect { klass.new('test').open_channel }.not_to raise_exception
    # expect { klass.new('test', {durable: false})}.not_to raise_exception
    # expect {klass.new('test').recreate_queue(nil, 'test')}.not_to raise_exception
    expect do
      foo = klass.new('test')
      foo.recreate_queue('test')
    end.not_to raise_exception

    # expect (klass.new('test').queue_name ).to be_a String
    expect do
      foo = klass.new('test')
      foo.delete
    end.not_to raise_exception
  end
end
