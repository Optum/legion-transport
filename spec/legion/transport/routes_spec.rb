# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Transport::Routes do
  it 'is a module' do
    expect(Legion::Transport::Routes).to be_a(Module)
  end

  it 'responds to registered' do
    expect(Legion::Transport::Routes).to respond_to(:registered)
  end
end
