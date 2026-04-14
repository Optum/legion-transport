# frozen_string_literal: true

require 'spec_helper'
require 'legion/transport/messages/subtask'

RSpec.describe Legion::Transport::Messages::SubTask do
  describe '#message' do
    it 'includes engine when provided' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, {
                                       transformation: '{"template":"test"}',
                                       conditions:     nil,
                                       results:        { data: 'value' },
                                       engine:         'llm'
                                     })
      msg = instance.message
      expect(msg[:engine]).to eq('llm')
    end

    it 'omits engine when not provided' do
      instance = described_class.allocate
      instance.instance_variable_set(:@options, {
                                       transformation: '{"template":"test"}',
                                       conditions:     nil,
                                       results:        { data: 'value' }
                                     })
      msg = instance.message
      expect(msg).not_to have_key(:engine)
    end
  end
end
