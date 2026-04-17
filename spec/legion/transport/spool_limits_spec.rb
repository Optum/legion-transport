# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Legion::Transport::Spool, 'limits and envelope (#19)' do
  let(:spool_dir) { Dir.mktmpdir('legion-spool-limits') }

  before do
    described_class.reset!
    described_class.setup(directory: spool_dir, max_file_bytes: 10_485_760, max_total_bytes: 512,
                          max_files: 100, max_age_seconds: 259_200)
  end

  after { FileUtils.rm_rf(spool_dir) }

  describe 'max_total_bytes enforcement' do
    it 'evicts oldest files when total bytes exceeds max_total_bytes' do
      # Write enough data to exceed the 512-byte limit across multiple files
      15.times do |i|
        described_class.write(exchange: 'task', routing_key: 'test', payload: { data: 'x' * 50, index: i })
      end

      total = Dir.glob(File.join(spool_dir, '*.jsonl')).sum { |f| File.size(f) }
      expect(total).to be <= 512 * 2
    end
  end

  describe 'spool envelope preservation' do
    it 'preserves headers in spooled message' do
      described_class.reset!
      described_class.setup(directory: spool_dir)
      described_class.write(
        exchange:    'task',
        routing_key: 'test.run',
        payload:     { foo: 'bar' },
        headers:     { 'x-priority' => 5, 'legion_protocol_version' => '2.0' }
      )

      messages = []
      described_class.drain { |msg| messages << msg }
      expect(messages.first[:headers]).to eq({ :'x-priority' => 5, legion_protocol_version: '2.0' })
    end

    it 'preserves priority in spooled message' do
      described_class.reset!
      described_class.setup(directory: spool_dir)
      described_class.write(exchange: 'task', routing_key: 'test.run', payload: { foo: 'bar' }, priority: 10)

      messages = []
      described_class.drain { |msg| messages << msg }
      expect(messages.first[:priority]).to eq(10)
    end

    it 'preserves message_id in spooled message' do
      described_class.reset!
      described_class.setup(directory: spool_dir)
      described_class.write(exchange: 'task', routing_key: 'test.run', payload: {}, message_id: 'abc-123')

      messages = []
      described_class.drain { |msg| messages << msg }
      expect(messages.first[:message_id]).to eq('abc-123')
    end

    it 'preserves correlation_id in spooled message' do
      described_class.reset!
      described_class.setup(directory: spool_dir)
      described_class.write(exchange: 'task', routing_key: 'test.run', payload: {}, correlation_id: 'corr-456')

      messages = []
      described_class.drain { |msg| messages << msg }
      expect(messages.first[:correlation_id]).to eq('corr-456')
    end

    it 'preserves persistent flag in spooled message' do
      described_class.reset!
      described_class.setup(directory: spool_dir)
      described_class.write(exchange: 'task', routing_key: 'test.run', payload: {}, persistent: true)

      messages = []
      described_class.drain { |msg| messages << msg }
      expect(messages.first[:persistent]).to be true
    end
  end

  describe 'streaming count and drain' do
    it 'count does not load full file into memory (uses line streaming)' do
      described_class.reset!
      described_class.setup(directory: spool_dir)
      5.times { |i| described_class.write(exchange: 'task', routing_key: 'test', payload: { i: i }) }

      expect(File).not_to receive(:readlines)
      expect(described_class.count).to eq(5)
    end
  end
end
