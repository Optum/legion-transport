require 'spec_helper'

RSpec.describe Legion::Transport::Settings do
  it 'returns a hash regardless of if vault works' do
    expect(described_class.grab_vault_creds).to be_a Hash
    Legion::Settings[:crypt][:vault][:connected] = true
    expect(described_class.grab_vault_creds).to be_a Hash
  end
end
