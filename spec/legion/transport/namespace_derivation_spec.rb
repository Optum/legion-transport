# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Namespace derivation' do
  def stub_queue_class(full_name)
    Class.new(Legion::Transport::Queue) do
      define_method(:self_name) { full_name }

      define_singleton_method(:ancestors) { [self, Legion::Transport::Queue] }
      define_singleton_method(:to_s) { full_name }
    end
  end

  def stub_exchange_class(full_name)
    Class.new(Legion::Transport::Exchange) do
      define_singleton_method(:ancestors) { [self, Legion::Transport::Exchange] }
      define_singleton_method(:to_s) { full_name }
    end
  end

  def stub_message_class(full_name)
    Class.new(Legion::Transport::Message) do
      define_singleton_method(:ancestors) { [self, Legion::Transport::Message] }
      define_singleton_method(:to_s) { full_name }
    end
  end

  describe 'Queue#queue_name' do
    it 'handles standard single-level extension' do
      klass = stub_queue_class('Legion::Extensions::Github::Transport::Queues::Repos')
      instance = klass.allocate
      expect(instance.queue_name).to eq('github.repos')
    end

    it 'handles nested sub-module extension' do
      klass = stub_queue_class('Legion::Extensions::Github::App::Transport::Queues::Auth')
      instance = klass.allocate
      expect(instance.queue_name).to eq('github.app.auth')
    end

    it 'handles deeply nested sub-module extension' do
      klass = stub_queue_class('Legion::Extensions::Dynatrace::Metrics::Transport::Queues::Metrics')
      instance = klass.allocate
      expect(instance.queue_name).to eq('dynatrace.metrics.metrics')
    end

    it 'handles CamelCase class names' do
      klass = stub_queue_class('Legion::Extensions::SettingsObjects::Transport::Queues::SchemaValidation')
      instance = klass.allocate
      expect(instance.queue_name).to eq('settings_objects.schema_validation')
    end

    it 'handles acronym-style class names' do
      klass = stub_queue_class('Legion::Extensions::HTTPClient::Transport::Queues::APIRequest')
      instance = klass.allocate
      expect(instance.queue_name).to eq('http_client.api_request')
    end

    it 'handles extension without Transport wrapper' do
      klass = stub_queue_class('Legion::Extensions::Knowledge::Queues::Chunker')
      instance = klass.allocate
      expect(instance.queue_name).to eq('knowledge.chunker')
    end
  end

  describe 'Queue#dlx_exchange_name' do
    it 'handles standard single-level extension' do
      klass = stub_queue_class('Legion::Extensions::Github::Transport::Queues::Repos')
      instance = klass.allocate
      expect(instance.dlx_exchange_name).to eq('github.dlx')
    end

    it 'handles nested sub-module extension' do
      klass = stub_queue_class('Legion::Extensions::Github::App::Transport::Queues::Auth')
      instance = klass.allocate
      expect(instance.dlx_exchange_name).to eq('github.app.dlx')
    end

    it 'handles deeply nested sub-module extension' do
      klass = stub_queue_class('Legion::Extensions::Dynatrace::Metrics::Transport::Queues::Metrics')
      instance = klass.allocate
      expect(instance.dlx_exchange_name).to eq('dynatrace.metrics.dlx')
    end
  end

  describe 'Exchange#exchange_name' do
    it 'handles standard single-level extension' do
      klass = stub_exchange_class('Legion::Extensions::Github::Transport::Exchanges::Github')
      instance = klass.allocate
      expect(instance.exchange_name).to eq('github')
    end

    it 'handles nested sub-module extension' do
      klass = stub_exchange_class('Legion::Extensions::Github::App::Transport::Exchanges::Github')
      instance = klass.allocate
      expect(instance.exchange_name).to eq('github.app')
    end

    it 'returns last segment for base Exchange class' do
      instance = Legion::Transport::Exchange.allocate
      expect(instance.exchange_name).to eq('exchange')
    end
  end

  describe 'Message#exchange_name' do
    it 'constructs correct constant path for single-level extension' do
      klass = stub_message_class('Legion::Extensions::Github::Transport::Messages::Push')
      instance = klass.allocate
      expect(instance.send(:exchange_name)).to eq('Legion::Extensions::Github::Transport::Exchanges::Github')
    end

    it 'constructs correct constant path for nested extension' do
      klass = stub_message_class('Legion::Extensions::Github::App::Transport::Messages::Auth')
      instance = klass.allocate
      expect(instance.send(:exchange_name)).to eq('Legion::Extensions::Github::App::Transport::Exchanges::Github')
    end
  end

  describe 'Common#derive_segments' do
    it 'stops at Transport boundary' do
      klass = stub_queue_class('Legion::Extensions::Github::App::Transport::Queues::Auth')
      instance = klass.allocate
      expect(instance.send(:derive_segments)).to eq(%w[github app])
    end

    it 'stops at Runners boundary' do
      klass = stub_queue_class('Legion::Extensions::Github::App::Runners::Auth')
      instance = klass.allocate
      expect(instance.send(:derive_segments)).to eq(%w[github app])
    end

    it 'stops at Actors boundary' do
      klass = stub_queue_class('Legion::Extensions::Github::Actors::Polling')
      instance = klass.allocate
      expect(instance.send(:derive_segments)).to eq(%w[github])
    end

    it 'stops at Data boundary' do
      klass = stub_queue_class('Legion::Extensions::Github::Data::Models::Repo')
      instance = klass.allocate
      expect(instance.send(:derive_segments)).to eq(%w[github])
    end

    it 'falls back to last part when no Extensions module' do
      instance = Legion::Transport::Queue.allocate
      expect(instance.send(:derive_segments)).to eq(%w[queue])
    end
  end

  describe 'Common#camelize_to_snake' do
    let(:instance) { Legion::Transport::Queue.allocate }

    {
      'Github'          => 'github',
      'TaskUpdate'      => 'task_update',
      'HTTPClient'      => 'http_client',
      'SettingsObjects' => 'settings_objects',
      'APIRequest'      => 'api_request',
      'OAuth'           => 'o_auth',
      'SimpleA'         => 'simple_a'
    }.each do |input, expected|
      it "converts #{input} to #{expected}" do
        expect(instance.send(:camelize_to_snake, input)).to eq(expected)
      end
    end
  end
end
