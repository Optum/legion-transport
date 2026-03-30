# frozen_string_literal: true

require 'legion/transport/connection'

module Legion
  module Transport
    module Common
      NAMESPACE_BOUNDARIES = %w[Actor Actors Runners Helpers Transport Data Queues Queue Exchanges Exchange Messages Message].freeze

      def open_channel(_options = {})
        @channel = Legion::Transport::Connection.channel
      end

      def channel_open?
        channel.open?
      end

      def options_builder(first, *args)
        final_options = nil
        args.each do |option|
          final_options = if final_options.nil?
                            deep_merge(first, option)
                          else
                            deep_merge(final_options, option)
                          end
        end
        final_options
      end

      # rubocop:disable all
      def deep_merge(original, new)
        {} unless original.is_a?(Hash) && new.is_a?(Hash)
        original unless new.is_a? Hash
        new unless original.is_a? Hash
        new if original.nil? || original.empty?
        original if new.nil? || new.empty?

        new.each do |k, v|
          unless original.key?(k)
            original[k] = v
            next
          end

          original[k.to_sym] = if [original[k.to_sym], new[k.to_sym]].all? { |a| a.is_a? Hash }
                          deep_merge(original[k], new[k])
                        else
                          new[k]
                        end
        end
        original
      end
      # rubocop:enable all

      def channel
        @channel ||= Legion::Transport::Connection.channel
      end

      def close!
        Legion::Transport.logger.error 'close! called'
        return false unless Legion::Transport::Connection.channel_open?

        Legion::Transport::Connection.channel.close
      end

      def close
        Legion::Transport.logger.error 'close called'
        Legion::Transport.logger.warn 'close called, but method is called close!'
        close!
      end

      def generate_consumer_tag(lex_name: nil, runner_name: nil, thread: Thread.current.object_id)
        tag = "#{Legion::Settings[:client][:name]}_"
        tag.concat("#{lex_name}_") unless lex_name.nil?
        tag.concat("#{runner_name}_") unless runner_name.nil?
        tag.concat("#{thread}_")
        tag.concat(SecureRandom.hex)
        tag
      end

      private

      def camelize_to_snake(str)
        str.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .downcase
      end

      def derive_extension_parts
        parts = self.class.ancestors.first.to_s.split('::')
        ext_idx = parts.index('Extensions')
        return [parts.last] unless ext_idx

        ext_parts = []
        ((ext_idx + 1)...parts.length).each do |i|
          break if NAMESPACE_BOUNDARIES.include?(parts[i])

          ext_parts << parts[i]
        end
        ext_parts.empty? ? [parts[ext_idx + 1]] : ext_parts
      end

      def derive_segments
        derive_extension_parts.map { |p| camelize_to_snake(p) }
      end

      def derive_leaf
        parts = self.class.ancestors.first.to_s.split('::')
        camelize_to_snake(parts.last)
      end
    end
  end
end
