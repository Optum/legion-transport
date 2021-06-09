begin
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
    add_group 'Messages', 'lib/legion/transport/messages'
    add_group 'Exchanges', 'lib/legion/transport/exchanges'
    add_group 'Queues', 'lib/legion/transport/queues'
    add_group 'Connections', 'lib/legion/transport/connections'
    project_name 'Legion::Transport'
  end
rescue LoadError
  puts 'Failed to load file for coverage reports, continuing without it'
end

require 'bundler/setup'

require 'legion/settings'
Legion::Settings.load
require 'legion/transport'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
