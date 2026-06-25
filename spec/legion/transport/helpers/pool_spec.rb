# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Transport::Helpers::Pool do
  let(:session) { instance_double('Bunny::Session', open?: true, closed?: false, close: nil) }
  let(:factory) { -> { session } }

  subject(:pool) { described_class.new(size: 2, timeout: 0.1, &factory) }

  describe '#checkout' do
    it 'creates a new connection when the pool is empty' do
      expect(pool.checkout).to eq(session)
    end

    it 'creates distinct connections up to configured size' do
      session2 = instance_double('Bunny::Session', open?: true, closed?: false, close: nil)
      sessions = [session, session2]
      call_count = 0
      multi_pool = described_class.new(size: 2, timeout: 0.1) do
        sessions[call_count].tap { call_count += 1 }
      end

      first  = multi_pool.checkout
      second = multi_pool.checkout
      expect([first, second]).to match_array([session, session2])
    end

    it 'returns a checked-in connection before creating new ones' do
      pool.checkout # fills slot
      pool.checkin(session)
      # Should return session from available, not create new
      expect(pool.checkout).to eq(session)
    end

    it 'raises PoolTimeout when pool is exhausted and timeout expires' do
      session2 = instance_double('Bunny::Session', open?: true, closed?: false, close: nil)
      sessions = [session, session2]
      call_count = 0
      full_pool = described_class.new(size: 2, timeout: 0.05) do
        sessions[call_count].tap { call_count += 1 }
      end

      full_pool.checkout
      full_pool.checkout

      # Pool is full (both in use, nothing available)
      expect { full_pool.checkout }.to raise_error(Legion::Transport::PoolTimeout)
    end

    it 'drops closed connections and creates new ones' do
      closed  = instance_double('Bunny::Session', open?: false, closed?: true, close: nil)
      fresh   = instance_double('Bunny::Session', open?: true,  closed?: false, close: nil)
      sessions = [fresh]
      replace_pool = described_class.new(size: 1, timeout: 0.1) { sessions.shift }

      # Put a closed connection in available
      replace_pool.instance_variable_get(:@available) << closed
      result = replace_pool.checkout
      expect(result).to eq(fresh)
    end
  end

  describe '#checkin' do
    it 'makes a connection available for re-checkout' do
      pool.checkout
      pool.checkin(session)
      expect(pool.checkout).to eq(session)
    end
  end

  describe '#size' do
    it 'returns 0 when pool is empty' do
      expect(pool.size).to eq(0)
    end

    it 'counts in-use connections' do
      pool.checkout
      expect(pool.size).to eq(1)
    end

    it 'counts available connections' do
      pool.checkout
      pool.checkin(session)
      expect(pool.size).to eq(1)
    end
  end

  describe '#shutdown' do
    it 'closes all connections' do
      pool.checkout
      expect(session).to receive(:close)
      pool.shutdown
    end

    it 'clears the internal connection list' do
      pool.checkout
      pool.shutdown
      expect(pool.size).to eq(0)
    end
  end

  describe '#connected?' do
    it 'returns false when pool is empty' do
      expect(pool.connected?).to be false
    end

    it 'returns true when an in-use open connection exists' do
      pool.checkout
      expect(pool.connected?).to be true
    end

    it 'returns true when an available open connection exists' do
      pool.checkout
      pool.checkin(session)
      expect(pool.connected?).to be true
    end

    it 'returns false when all connections are closed' do
      closed = instance_double('Bunny::Session', open?: false, closed?: true, close: nil)
      closed_pool = described_class.new(size: 1, timeout: 0.05) { closed }
      closed_pool.instance_variable_get(:@in_use) << closed
      expect(closed_pool.connected?).to be false
    end
  end

  describe 'thread safety' do
    it 'handles 10 concurrent checkouts without raising errors' do
      sessions = Array.new(10) do
        instance_double('Bunny::Session', open?: true, closed?: false, close: nil)
      end
      call_count = 0
      mutex = Mutex.new
      thread_pool = described_class.new(size: 10, timeout: 2) do
        mutex.synchronize do
          sessions[call_count].tap { call_count += 1 }
        end
      end

      threads = 10.times.map do
        Thread.new { thread_pool.checkout }
      end

      results = threads.map(&:value)
      expect(results.compact.size).to eq(10)
    end
  end
end
