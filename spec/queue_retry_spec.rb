# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Transport::Queue do
  describe '#nack_or_dlq' do
    let(:queue) { described_class.allocate }
    let(:tag) { 'delivery-tag-1' }

    before do
      allow(queue).to receive(:reject)
    end

    it 'rejects with requeue: true when retry_count is below threshold' do
      queue.nack_or_dlq(tag, retry_count: 0, threshold: 2)
      expect(queue).to have_received(:reject).with(tag, requeue: true)
    end

    it 'rejects with requeue: true when retry_count is 1 below threshold' do
      queue.nack_or_dlq(tag, retry_count: 1, threshold: 2)
      expect(queue).to have_received(:reject).with(tag, requeue: true)
    end

    it 'dead-letters when retry_count equals threshold' do
      queue.nack_or_dlq(tag, retry_count: 2, threshold: 2)
      expect(queue).to have_received(:reject).with(tag, requeue: false)
    end

    it 'dead-letters when retry_count exceeds threshold' do
      queue.nack_or_dlq(tag, retry_count: 5, threshold: 2)
      expect(queue).to have_received(:reject).with(tag, requeue: false)
    end

    it 'dead-letters immediately when threshold is 0' do
      queue.nack_or_dlq(tag, retry_count: 0, threshold: 0)
      expect(queue).to have_received(:reject).with(tag, requeue: false)
    end
  end
end
