# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Transport::Connection do
  describe '.lite_mode?' do
    it 'returns true when TYPE is local' do
      stub_const('Legion::Transport::TYPE', 'local')
      expect(described_class.lite_mode?).to be true
    end

    it 'returns false when TYPE is bunny' do
      expect(described_class.lite_mode?).to be false
    end
  end

  describe '.create_dedicated_session' do
    it 'returns an InProcess::Session in lite mode' do
      stub_const('Legion::Transport::TYPE', 'local')
      session = described_class.create_dedicated_session(name: 'test')
      expect(session).to be_a(Legion::Transport::InProcess::Session)
    end

    it 'responds to create_channel in lite mode' do
      stub_const('Legion::Transport::TYPE', 'local')
      session = described_class.create_dedicated_session(name: 'test')
      expect(session).to respond_to(:create_channel)
    end
  end
end
