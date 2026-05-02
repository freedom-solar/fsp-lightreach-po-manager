require 'rails_helper'

RSpec.describe Users::SessionsController, type: :controller do
  before do
    @request.env['devise.mapping'] = Devise.mappings[:user]
  end

  describe 'GET #new' do
    it 'renders the sign in page' do
      get :new
      expect(response).to have_http_status(:success)
    end
  end

  describe 'DELETE #destroy' do
    let(:user) { create(:user) }

    before do
      sign_in user
    end

    it 'signs out the user' do
      delete :destroy
      expect(controller.current_user).to be_nil
    end

    it 'redirects after sign out' do
      delete :destroy
      expect(response).to have_http_status(:redirect)
    end
  end
end
