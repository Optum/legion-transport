# frozen_string_literal: true

require 'fileutils'
require 'securerandom'

module Legion
  module Transport
    module Spool
      class << self
        def setup(directory: nil, max_file_bytes: 10_485_760, max_total_bytes: 524_288_000,
                  max_files: 100, max_age_seconds: 259_200)
          @directory = directory || File.expand_path('~/.legionio/spool')
          @max_file_bytes = max_file_bytes
          @max_total_bytes = max_total_bytes
          @max_files = max_files
          @max_age_seconds = max_age_seconds
          @current_file = nil
          @mutex = Mutex.new

          FileUtils.mkdir_p(@directory)
        end

        def write(exchange:, routing_key:, payload:)
          setup unless @directory

          @mutex.synchronize do
            evict_oldest if over_limits?

            line = Legion::JSON.dump({
                                       exchange: exchange,
                                       routing_key: routing_key,
                                       payload: payload,
                                       spooled_at: Time.now.iso8601
                                     })

            file = current_file
            File.open(file, 'a') { |f| f.puts(line) }

            rotate_if_needed
          end
        rescue StandardError => e
          Legion::Logging.warn { "Spool write failed: #{e.message}" } if defined?(Legion::Logging)
        end

        def drain
          setup unless @directory

          sorted_files.each do |file|
            lines = File.readlines(file).map(&:strip).reject(&:empty?)
            lines.each do |line|
              msg = Legion::JSON.load(line)
              yield(msg)
            end
            File.delete(file)
          rescue StandardError => e
            Legion::Logging.warn { "Spool drain error on #{file}: #{e.message}" } if defined?(Legion::Logging)
            break
          end
        end

        def count
          setup unless @directory

          sorted_files.sum do |file|
            File.readlines(file).count { |l| !l.strip.empty? }
          rescue StandardError
            0
          end
        end

        def evict_stale
          setup unless @directory

          cutoff = Time.now - @max_age_seconds
          sorted_files.each do |file|
            File.delete(file) if File.mtime(file) < cutoff
          rescue StandardError
            nil
          end
        end

        def reset!
          @directory = nil
          @current_file = nil
          @mutex = nil
          @max_file_bytes = nil
          @max_total_bytes = nil
          @max_files = nil
          @max_age_seconds = nil
        end

        attr_reader :max_file_bytes

        private

        def sorted_files
          Dir.glob(File.join(@directory, '*.jsonl')).sort
        end

        def current_file
          @current_file ||= new_file_path
          @current_file = new_file_path unless File.exist?(@current_file)
          @current_file
        end

        def new_file_path
          File.join(@directory, "spool-#{Time.now.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}.jsonl")
        end

        def rotate_if_needed
          return unless File.exist?(@current_file) && File.size(@current_file) >= @max_file_bytes

          @current_file = nil
        end

        def over_limits?
          files = sorted_files
          return true if files.size >= @max_files

          total = files.sum do |f|
            File.size(f)
          rescue StandardError
            0
          end
          total >= @max_total_bytes
        end

        def evict_oldest
          files = sorted_files
          while files.size >= @max_files
            begin
              File.delete(files.shift)
            rescue StandardError
              break
            end
          end
        end
      end
    end
  end
end
