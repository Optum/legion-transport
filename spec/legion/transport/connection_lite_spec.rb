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

    it 'uses create_session_with_failover and starts the session in non-lite mode' do
      fake_session = instance_double('Bunny::Session', start: nil)
      allow(described_class).to receive(:create_session_with_failover)
        .with(connection_name: 'test')
        .and_return(fake_session)

      result = described_class.create_dedicated_session(name: 'test')

      expect(described_class).to have_received(:create_session_with_failover).with(connection_name: 'test')
      expect(fake_session).to have_received(:start)
      expect(result).to eq(fake_session)
    end
  end
end
