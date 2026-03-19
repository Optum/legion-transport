# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Legion::Transport::Spool do
  let(:spool_dir) { Dir.mktmpdir('legion-spool') }

  before do
    described_class.reset!
    described_class.setup(directory: spool_dir, max_file_bytes: 1024, max_total_bytes: 4096, max_files: 5,
                          max_age_seconds: 259_200)
  end

  after { FileUtils.rm_rf(spool_dir) }

  describe '.write' do
    it 'writes a message to a spool file' do
      described_class.write(exchange: 'task', routing_key: 'test.run', payload: { foo: 'bar' })
      expect(described_class.count).to eq(1)
    end

    it 'creates JSONL files with .jsonl extension' do
      described_class.write(exchange: 'task', routing_key: 'test.run', payload: { foo: 'bar' })
      files = Dir.glob(File.join(spool_dir, '*.jsonl'))
      expect(files.size).to eq(1)
    end

    it 'rotates to new file when max_file_bytes exceeded' do
      10.times do |i|
        described_class.write(exchange: 'task', routing_key: 'test.run',
                              payload: { data: 'x' * 100, index: i })
      end
      files = Dir.glob(File.join(spool_dir, '*.jsonl'))
      expect(files.size).to be > 1
    end

    it 'drops messages when max_files exceeded' do
      allow(described_class).to receive(:max_file_bytes).and_return(50)
      100.times do |i|
        described_class.write(exchange: 'task', routing_key: 'test', payload: { i: i })
      end
      files = Dir.glob(File.join(spool_dir, '*.jsonl'))
      expect(files.size).to be <= 5
    end
  end

  describe '.drain' do
    it 'yields each spooled message in order' do
      3.times { |i| described_class.write(exchange: 'task', routing_key: "test.#{i}", payload: { i: i }) }

      messages = []
      described_class.drain { |msg| messages << msg }
      expect(messages.size).to eq(3)
      expect(messages.first[:payload][:i]).to eq(0)
    end

    it 'deletes files after successful drain' do
      described_class.write(exchange: 'task', routing_key: 'test', payload: { a: 1 })
      described_class.drain { |_msg| true }
      expect(Dir.glob(File.join(spool_dir, '*.jsonl'))).to be_empty
    end

    it 'keeps files when drain block raises' do
      described_class.write(exchange: 'task', routing_key: 'test', payload: { a: 1 })
      described_class.drain { |_msg| raise 'publish failed' } rescue nil # rubocop:disable Style/RescueModifier
      expect(Dir.glob(File.join(spool_dir, '*.jsonl')).size).to eq(1)
    end
  end

  describe '.count' do
    it 'returns total message count across all files' do
      5.times { |i| described_class.write(exchange: 'task', routing_key: 'test', payload: { i: i }) }
      expect(described_class.count).to eq(5)
    end
  end

  describe '.evict_stale' do
    it 'removes files older than max_age_seconds' do
      described_class.write(exchange: 'task', routing_key: 'test', payload: { old: true })
      files = Dir.glob(File.join(spool_dir, '*.jsonl'))
      FileUtils.touch(files.first, mtime: Time.now - 300_000)
      described_class.evict_stale
      expect(Dir.glob(File.join(spool_dir, '*.jsonl'))).to be_empty
    end
  end

  describe '.reset!' do
    it 'clears internal state' do
      described_class.write(exchange: 'task', routing_key: 'test', payload: { a: 1 })
      described_class.reset!
      expect { described_class.write(exchange: 'task', routing_key: 'test', payload: { a: 1 }) }.not_to raise_error
    end
  end
end
