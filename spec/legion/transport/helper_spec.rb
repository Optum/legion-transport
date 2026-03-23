# frozen_string_literal: true

RSpec.describe Legion::Transport::Helper do
  describe '#transport_connected?' do
    let(:test_class) do
      Class.new do
        include Legion::Transport::Helper
      end
    end
    let(:instance) { test_class.new }

    it 'returns true when transport is connected' do
      allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: true })
      expect(instance.transport_connected?).to be true
    end

    it 'returns false when transport is not connected' do
      allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: false })
      expect(instance.transport_connected?).to be false
    end
  end

  describe '#transport_path' do
    let(:test_class) do
      Class.new do
        include Legion::Transport::Helper

        def full_path
          '/opt/legion/extensions/lex-test'
        end
      end
    end
    let(:instance) { test_class.new }

    it 'returns the transport subdirectory path' do
      expect(instance.transport_path).to eq('/opt/legion/extensions/lex-test/transport')
    end

    it 'memoizes the result' do
      first = instance.transport_path
      expect(instance.transport_path).to equal(first)
    end
  end

  describe '#transport_class' do
    let(:lex_transport) { Module.new }
    let(:lex_class) do
      mod = Module.new
      mod.const_set(:Transport, lex_transport)
      mod
    end
    let(:test_class) do
      lc = lex_class
      Class.new do
        include Legion::Transport::Helper

        define_method(:lex_class) { lc }
      end
    end
    let(:instance) { test_class.new }

    it 'returns the transport module for the lex class' do
      expect(instance.transport_class).to eq(lex_transport)
    end
  end
end
