# frozen_string_literal: true

require 'fileutils'
require 'legion/logging/helper'
require 'securerandom'

module Legion
  module Transport
    module Spool
      class << self
        include Legion::Logging::Helper

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
          log.info "Spool initialized directory=#{@directory} max_files=#{@max_files} " \
                   "max_total_bytes=#{@max_total_bytes} max_file_bytes=#{@max_file_bytes}"
        end

        def write(exchange:, routing_key:, payload:, **envelope_opts)
          setup unless @directory

          @mutex.synchronize do
            evict_oldest if over_limits?

            envelope = {
              exchange:    exchange,
              routing_key: routing_key,
              payload:     payload,
              spooled_at:  Time.now.iso8601
            }
            %i[headers priority message_id correlation_id persistent].each do |key|
              envelope[key] = envelope_opts[key] unless envelope_opts[key].nil?
            end

            line = Legion::JSON.dump(envelope)
            file = current_file
            File.open(file, 'a') { |f| f.puts(line) }

            rotate_if_needed
          end
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: 'transport.spool.write',
                           directory: @directory, exchange: exchange, routing_key: routing_key)
        end

        def drain(&)
          setup unless @directory

          sorted_files.each do |file|
            messages = []
            stream_lines(file) { |line| messages << Legion::JSON.load(line) }
            log.info "Draining spool file=#{file} messages=#{messages.size}"
            messages.each(&)
            File.delete(file)
          rescue StandardError => e
            handle_exception(e, level: :warn, handled: true, operation: 'transport.spool.drain', file: file)
            break
          end
        end

        def count
          setup unless @directory

          sorted_files.sum do |file|
            n = 0
            stream_lines(file) { n += 1 }
            n
          rescue StandardError => e
            handle_exception(e, level: :warn, handled: true, operation: 'transport.spool.count', file: file)
            0
          end
        end

        def evict_stale
          setup unless @directory

          cutoff = Time.now - @max_age_seconds
          sorted_files.each do |file|
            next unless File.mtime(file) < cutoff

            File.delete(file)
            log.info "Evicted stale spool file=#{file}"
          rescue StandardError => e
            handle_exception(e, level: :warn, handled: true, operation: 'transport.spool.evict_stale', file: file)
            nil
          end
        end

        def reset!
          log.info 'Spool reset'
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
          Dir.glob(File.join(@directory, '*.jsonl'))
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

          log.debug "Rotating spool file=#{@current_file}"
          @current_file = nil
        end

        def over_limits?
          files = sorted_files
          return true if files.size >= @max_files

          total = files.sum do |f|
            File.size(f)
          rescue StandardError => e
            handle_exception(e, level: :warn, handled: true, operation: 'transport.spool.over_limits', file: f)
            0
          end
          total >= @max_total_bytes
        end

        def evict_oldest
          files = sorted_files
          loop do
            break if files.empty?
            break if files.size < @max_files && total_bytes(files) < @max_total_bytes

            begin
              oldest = files.shift
              File.delete(oldest)
              log.info "Evicted oldest spool file=#{oldest}"
            rescue StandardError => e
              handle_exception(e, level: :warn, handled: true, operation: 'transport.spool.evict_oldest')
              break
            end
          end
        end

        def total_bytes(files)
          files.sum do |f|
            File.size(f)
          rescue StandardError => e
            handle_exception(e, level: :warn, handled: true, operation: 'transport.spool.total_bytes', file: f)
            0
          end
        end

        def stream_lines(file)
          File.foreach(file) do |line|
            stripped = line.strip
            yield stripped unless stripped.empty?
          end
        end
      end
    end
  end
end
