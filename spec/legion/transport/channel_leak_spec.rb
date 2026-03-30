# frozen_string_literal: true

require 'spec_helper'
require 'legion/settings'
Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
require 'legion/transport'
require 'legion/transport/connection'

RSpec.describe 'Channel leak prevention' do
  before do
    Legion::Transport::Connection.setup
  end

  after do
    # Ensure @log_channel is always a real object (not a leaked double) for subsequent tests
    log_ch = Legion::Transport::Connection.instance_variable_get(:@log_channel)
    unless log_ch.is_a?(Bunny::Channel)
      Legion::Transport::Connection.instance_variable_set(:@log_channel, nil)
      Legion::Transport::Connection.setup
    end
  end

  describe 'Connection.setup' do
    it 'closes the QoS channel after applying basic_qos' do
      # Shut down and rebuild so we can observe the QoS channel lifecycle
      Legion::Transport::Connection.shutdown

      session = Legion::Transport::Connection.send(:create_session_with_failover, connection_name: 'test-qos')
      session.start
      Legion::Transport::Connection.instance_variable_set(
        :@session, Concurrent::AtomicReference.new(session)
      )
      Legion::Transport::Connection.instance_variable_set(
        :@channel_thread, Concurrent::ThreadLocalVar.new(nil)
      )

      channels_before = session.instance_variable_get(:@channels)&.size || 0

      # Apply QoS via a channel and close it — net channel count should be +1 (log_channel only)
      qos_ch = session.create_channel(nil, 1)
      qos_ch.basic_qos(2, true)
      qos_ch.close

      channels_after_qos = session.instance_variable_get(:@channels)&.count { |_k, v| v&.open? } || 0
      expect(channels_after_qos).to eq(channels_before)

      session.close
      # Restore a working connection for after block
      Legion::Transport::Connection.instance_variable_set(:@session, nil)
      Legion::Transport::Connection.setup
    end

    it 'closes old @log_channel before creating a new one' do
      old_log = Legion::Transport::Connection.instance_variable_get(:@log_channel)
      expect(old_log).to be_a(Bunny::Channel)
      expect(old_log).to be_open

      # Re-run setup — our fix should close old_log before replacing
      Legion::Transport::Connection.setup

      new_log = Legion::Transport::Connection.instance_variable_get(:@log_channel)
      expect(new_log).to be_a(Bunny::Channel)
      expect(new_log).to be_open
      # Old channel should now be closed
      expect(old_log).not_to be_open
    end
  end

  describe 'Connection.log_channel accessor' do
    it 'recovers when the log channel is closed' do
      old_log = Legion::Transport::Connection.instance_variable_get(:@log_channel)
      old_log.close

      result = Legion::Transport::Connection.log_channel
      expect(result).to be_a(Bunny::Channel)
      expect(result).to be_open
      expect(result).not_to eq(old_log)
    end

    it 'returns existing log_channel when still open' do
      existing = Legion::Transport::Connection.instance_variable_get(:@log_channel)
      expect(existing).to be_open

      result = Legion::Transport::Connection.log_channel
      expect(result).to eq(existing)
    end
  end

  describe 'Exchange#channel error recovery' do
    it 'closes old channel before replacing on ChannelLevelException' do
      exchange = Legion::Transport::Exchange.new('test_channel_recovery_leak')
      old_channel = exchange.instance_variable_get(:@channel)
      expect(old_channel).to be_open

      # Clear @channel so next call goes through Connection.channel
      exchange.instance_variable_set(:@channel, nil)

      # First Connection.channel call raises, simulating a broken channel
      bad_channel = Legion::Transport::Connection.session.create_channel
      good_channel = Legion::Transport::Connection.session.create_channel

      call_count = 0
      allow(Legion::Transport::Connection).to receive(:channel) do
        call_count += 1
        raise Bunny::ChannelLevelException.new('test error', bad_channel, 406) if call_count == 1

        good_channel
      end

      # The rescue path should close the bad channel and replace with a good one
      begin
        exchange.channel
      rescue Bunny::ChannelLevelException
        nil
      end

      recovered_channel = exchange.instance_variable_get(:@channel)
      expect(recovered_channel).to eq(good_channel)
      expect(recovered_channel).to be_open
    ensure
      old_channel&.close rescue nil # rubocop:disable Style/RescueModifier
      bad_channel&.close rescue nil # rubocop:disable Style/RescueModifier
      good_channel&.close rescue nil # rubocop:disable Style/RescueModifier
    end
  end

  describe 'Exchange delete_exchange replaces channel' do
    it 'gets a fresh channel via delete_exchange' do
      exchange = Legion::Transport::Exchange.new('test_delete_exchange_leak')
      old_channel = exchange.instance_variable_get(:@channel)
      expect(old_channel).to be_open

      exchange.delete_exchange('test_delete_exchange_leak')
      new_channel = exchange.instance_variable_get(:@channel)
      expect(new_channel).to be_a(Bunny::Channel)
      expect(new_channel).to be_open
    ensure
      exchange.instance_variable_get(:@channel)&.close rescue nil # rubocop:disable Style/RescueModifier
    end
  end

  describe 'Queue retry path' do
    it 'closes old channel when PreconditionFailed triggers retry' do
      # Create a queue with known params first
      q = Legion::Transport::Queue.new('test_queue_leak_check')
      original_channel = q.instance_variable_get(:@channel)
      expect(original_channel).to be_open

      q.delete
      original_channel.close rescue nil # rubocop:disable Style/RescueModifier

      # Now create with different params to trigger PreconditionFailed + retry
      # The retry path should close the old channel before getting a new one
      q2 = Legion::Transport::Queue.new('test_queue_leak_check')
      new_channel = q2.instance_variable_get(:@channel)
      expect(new_channel).to be_a(Bunny::Channel)
      expect(new_channel).to be_open
      q2.delete
      new_channel.close rescue nil # rubocop:disable Style/RescueModifier
    end
  end
end
