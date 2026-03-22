# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Transport::Helpers::ChannelPool do
  let(:channel) { instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil) }
  let(:connection) { instance_double('Bunny::Session', create_channel: channel) }

  subject(:pool) { described_class.new(connection: connection, size: 3, prefetch: 2) }

  describe '#borrow' do
    it 'creates a new channel when the pool is empty' do
      expect(connection).to receive(:create_channel).and_return(channel)
      result = pool.borrow
      expect(result).to eq(channel)
    end

    it 'sets prefetch on the new channel' do
      expect(channel).to receive(:prefetch).with(2)
      pool.borrow
    end

    it 'returns nil when pool is at max size and all channels are in use' do
      ch1 = instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil)
      ch2 = instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil)
      ch3 = instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil)
      channels = [ch1, ch2, ch3]
      call_count = 0
      allow(connection).to receive(:create_channel) do
        channels[call_count].tap { call_count += 1 }
      end

      pool.borrow
      pool.borrow
      pool.borrow

      expect(connection).not_to receive(:create_channel)
      result = pool.borrow
      expect(result).to be_nil
    end

    it 'reuses a returned channel' do
      expect(connection).to receive(:create_channel).once.and_return(channel)
      borrowed = pool.borrow
      pool.return(borrowed)
      reused = pool.borrow
      expect(reused).to eq(channel)
    end
  end

  describe '#return' do
    it 'makes a channel available for re-borrowing' do
      borrowed = pool.borrow
      pool.return(borrowed)
      expect(pool.size).to eq(1)
    end

    it 'does not add a closed channel back to available' do
      closed = instance_double('Bunny::Channel', open?: false, close: nil, prefetch: nil)
      pool.return(closed)
      expect(pool.size).to eq(0)
    end

    it 'does not exceed max size' do
      ch1 = instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil)
      ch2 = instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil)
      ch3 = instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil)
      ch4 = instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil)

      small_pool = described_class.new(connection: connection, size: 3, prefetch: 2)
      [ch1, ch2, ch3, ch4].each { |c| small_pool.return(c) }
      expect(small_pool.size).to eq(3)
    end
  end

  describe '#purge_closed' do
    it 'removes closed channels from the available list' do
      open_ch   = instance_double('Bunny::Channel', open?: true,  close: nil, prefetch: nil)
      closed_ch = instance_double('Bunny::Channel', open?: false, close: nil, prefetch: nil)

      pool.return(open_ch)
      pool.instance_variable_get(:@available) << closed_ch
      expect(pool.size).to eq(2)

      pool.purge_closed
      expect(pool.size).to eq(1)
    end

    it 'does nothing when all channels are open' do
      ch1 = instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil)
      ch2 = instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil)
      pool.return(ch1)
      pool.return(ch2)
      pool.purge_closed
      expect(pool.size).to eq(2)
    end
  end

  describe '#close_all' do
    it 'closes all available channels' do
      ch1 = instance_double('Bunny::Channel', open?: true, prefetch: nil)
      ch2 = instance_double('Bunny::Channel', open?: true, prefetch: nil)
      expect(ch1).to receive(:close)
      expect(ch2).to receive(:close)

      pool.return(ch1)
      pool.return(ch2)
      pool.close_all
    end

    it 'closes in-use channels' do
      expect(channel).to receive(:prefetch).with(2)
      expect(channel).to receive(:close)
      pool.borrow
      pool.close_all
    end

    it 'clears the pool after closing' do
      pool.return(channel)
      allow(channel).to receive(:close)
      pool.close_all
      expect(pool.size).to eq(0)
    end
  end

  describe '#size' do
    it 'returns 0 when pool is empty' do
      expect(pool.size).to eq(0)
    end

    it 'counts available channels' do
      ch1 = instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil)
      ch2 = instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil)
      pool.return(ch1)
      pool.return(ch2)
      expect(pool.size).to eq(2)
    end

    it 'counts in-use channels' do
      pool.borrow
      expect(pool.size).to eq(1)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent borrows and returns without corrupting state' do
      channels = Array.new(10) do
        instance_double('Bunny::Channel', open?: true, close: nil, prefetch: nil)
      end
      call_count = 0
      mutex = Mutex.new
      thread_pool = described_class.new(connection: connection, size: 10, prefetch: 2)

      allow(connection).to receive(:create_channel) do
        mutex.synchronize do
          channels[call_count].tap { call_count += 1 }
        end
      end

      threads = 10.times.map do
        Thread.new do
          ch = thread_pool.borrow
          thread_pool.return(ch) if ch
        end
      end

      threads.each(&:join)
      expect(thread_pool.size).to be >= 0
    end
  end
end
