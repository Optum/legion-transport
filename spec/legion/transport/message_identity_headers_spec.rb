# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Identity headers' do
  let(:message_class) do
    Class.new(Legion::Transport::Message) do
      def exchange = nil

      def routing_key = 'test.key'

      def valid? = true
    end
  end

  let(:identity_hash) do
    {
      canonical_name: 'agent.local',
      id:             'abc-123',
      kind:           'agent',
      mode:           'prod',
      source:         'gaia'
    }
  end

  before do
    stub_const('Legion::Identity::Process', Class.new do
      class << self
        attr_accessor :identity_hash_value, :resolved_flag
      end

      def self.identity_hash = identity_hash_value
      def self.resolved? = resolved_flag
    end)

    Legion::Identity::Process.identity_hash_value = identity_hash
    Legion::Identity::Process.resolved_flag = true
  end

  it 'injects identity headers when identity is resolved' do
    msg = message_class.new(function: 'test')

    expect(msg.headers).to include(
      'x-legion-identity-canonical-name' => 'agent.local',
      'x-legion-identity-id'             => 'abc-123',
      'x-legion-identity-kind'           => 'agent',
      'x-legion-identity-mode'           => 'prod',
      'x-legion-identity-source'         => 'gaia'
    )
  end

  it 'keeps existing headers if identity injection fails' do
    msg = message_class.new(function: 'test', headers: { 'preserve' => 'me' })
    allow(Legion::Identity::Process).to receive(:identity_hash).and_raise(StandardError)

    expect { msg.headers }.not_to raise_error
    expect(msg.headers['preserve']).to eq('me')
  end
end
