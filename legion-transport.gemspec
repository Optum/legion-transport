# frozen_string_literal: true

require_relative 'lib/legion/transport/version'

Gem::Specification.new do |spec|
  spec.name = 'legion-transport'
  spec.version       = Legion::Transport::VERSION
  spec.authors       = ['Esity']
  spec.email         = %w[matthewdiverson@gmail.com ruby@optum.com]

  spec.summary       = 'Manages the connection to the transport tier(RabbitMQ)'
  spec.description   = 'The Gem to connect LegionIO and it\'s extensions to the transport tier'
  spec.homepage      = 'https://github.com/Optum/legion-transport'
  spec.license       = 'Apache-2.0'
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 2.5'
  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.test_files        = spec.files.select { |p| p =~ %r{^test/.*_test.rb} }
  spec.extra_rdoc_files  = %w[README.md LICENSE CHANGELOG.md]
  spec.metadata = {
    'bug_tracker_uri' => 'https://github.com/Optum/legion-transport/issues',
    'changelog_uri' => 'https://github.com/Optum/legion-transport/src/main/CHANGELOG.md',
    'documentation_uri' => 'https://github.com/Optum/legion-transport',
    'homepage_uri' => 'https://github.com/Optum/LegionIO',
    'source_code_uri' => 'https://github.com/Optum/legion-transport',
    'wiki_uri' => 'https://github.com/Optum/legion-transport/wiki'
  }

  spec.add_dependency 'bunny', '>= 2.17.0'
  spec.add_dependency 'concurrent-ruby', '>= 1.1.7'
  spec.add_dependency 'legion-json'
  spec.add_dependency 'legion-settings'
end
