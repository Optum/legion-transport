# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Transport::Settings do
  describe '.grab_vault_creds' do
    it 'returns a hash regardless of if vault works' do
      expect(described_class.grab_vault_creds).to be_a Hash
      Legion::Settings[:crypt][:vault][:connected] = true
      expect(described_class.grab_vault_creds).to be_a Hash
    end
  end

  describe '.connection' do
    subject(:connection) { described_class.connection }

    it 'returns port as an integer' do
      expect(connection[:port]).to be_a(Integer)
      expect(connection[:port]).to eq(5672)
    end
  end

  describe '.default' do
    subject(:defaults) { described_class.default }

    it 'includes connection settings' do
      expect(defaults[:connection]).to be_a(Hash)
      expect(defaults[:connection][:port]).to be_a(Integer)
    end
  end
end
