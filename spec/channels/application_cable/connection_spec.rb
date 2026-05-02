require 'rails_helper'

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) }

  context 'with valid user session' do
    it 'successfully connects' do
      connect '/cable', env: { 'warden' => double(user: user) }
      expect(connection.current_user).to eq(user)
    end
  end

  context 'without valid user session' do
    it 'rejects connection' do
      expect {
        connect '/cable'
      }.to have_rejected_connection
    end
  end

  context 'with nil warden user' do
    it 'rejects connection' do
      expect {
        connect '/cable', env: { 'warden' => double(user: nil) }
      }.to have_rejected_connection
    end
  end
end
