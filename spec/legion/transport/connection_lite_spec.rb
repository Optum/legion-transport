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
end
