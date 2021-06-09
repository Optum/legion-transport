require 'legion/transport/connection'

module Legion
  module Transport
    module Common
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
        false unless Legion::Transport::Connection.channel_open?
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
    end
  end
end
