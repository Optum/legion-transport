# frozen_string_literal: true

module Legion
  module Transport
    class Queue < Legion::Transport::CONNECTOR::Queue
      include Legion::Transport::Common

      def initialize(queue = queue_name, options = {})
        retries ||= 0
        @options = options
        merged = options_builder(default_options, queue_options, options)
        ensure_dlx(merged)
        super(channel, queue, merged)
      rescue Legion::Transport::CONNECTOR::PreconditionFailed => e
        handle_exception(e, level: :warn, handled: true, operation: 'transport.queue.initialize', queue: queue)
        retries.zero? ? retries = 1 : raise
        recreate_queue(queue)
        safely_close_channel(@channel)
        @channel = Legion::Transport::Connection.channel
        retry
      end

      def recreate_queue(queue)
        log.warn "Queue:#{queue} exists with wrong parameters, deleting and creating"
        tmp_channel = Legion::Transport::Connection.channel
        tmp_queue = ::Bunny::Queue.new(tmp_channel, queue, no_declare: true, passive: true)
        tmp_queue.delete
      ensure
        safely_close_channel(tmp_channel)
      end

      def default_options
        hash = Concurrent::Hash.new
        hash[:manual_ack] = true
        hash[:durable] = true
        hash[:exclusive] = false
        hash[:block] = false
        hash[:auto_delete] = false
        args = { 'x-queue-type': 'quorum' }
        args[:'x-dead-letter-exchange'] = dlx_exchange_name if dlx_enabled
        hash[:arguments] = args
        hash
      end

      def queue_options
        Concurrent::Hash.new
      end

      def dlx_enabled
        true
      end

      def dlx_exchange_name
        "#{derive_segments.join('.')}.dlx"
      end

      def ensure_dlx(merged_options)
        dlx_name = merged_options.dig(:arguments, :'x-dead-letter-exchange')
        return if dlx_name.nil? || dlx_name.empty?

        channel.exchange_declare(dlx_name, 'fanout', durable: true, auto_delete: false)
        channel.queue_declare("#{dlx_name}.queue", durable: true, auto_delete: false,
                                                    arguments: { 'x-queue-type': 'classic' })
        channel.queue_bind("#{dlx_name}.queue", dlx_name, routing_key: '#')
      rescue StandardError => e
        handle_exception(e, level: :warn, handled: true, operation: 'transport.queue.ensure_dlx', dlx: dlx_name)
      end

      def queue_name
        "#{derive_segments.join('.')}.#{derive_leaf}"
      end

      def delete(options = {})
        super
        true
      rescue Legion::Transport::CONNECTOR::PreconditionFailed => e
        handle_exception(e, level: :warn, handled: true, operation: 'transport.queue.delete')
        false
      end

      def acknowledge(delivery_tag)
        channel.acknowledge(delivery_tag)
      end

      def reject(delivery_tag, requeue: false)
        channel.reject(delivery_tag, requeue)
      end

      private

      def safely_close_channel(tmp_channel)
        tmp_channel&.close if tmp_channel&.open?
      rescue StandardError => e
        handle_exception(e, level: :warn, handled: true, operation: 'transport.queue.close_channel')
      end
    end
  end
end

require_relative 'queues/node'
require_relative 'queues/node_status'
require_relative 'queues/task_log'
require_relative 'queues/task_update'
require_relative 'queues/agent'
require_relative 'queues/region_outbound'
