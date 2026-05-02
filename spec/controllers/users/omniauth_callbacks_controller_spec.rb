require 'rails_helper'

RSpec.describe Users::OmniauthCallbacksController, type: :controller do
  before do
    request.env['devise.mapping'] = Devise.mappings[:user]
  end

  describe 'GET #google_oauth2' do
    let(:auth_hash) do
      OmniAuth::AuthHash.new({
        provider: 'google_oauth2',
        uid: '123456',
        info: {
          email: email,
          name: 'Test User'
        }
      })
    end

    before do
      request.env['omniauth.auth'] = auth_hash
    end

    context 'with valid @gofreedompower.com email' do
      let(:email) { 'test@gofreedompower.com' }

      it 'creates a new user' do
        expect {
          get :google_oauth2
        }.to change(User, :count).by(1)
      end

      it 'signs in the user' do
        get :google_oauth2
        expect(controller.current_user).to be_present
        expect(controller.current_user.email).to eq(email)
      end

      it 'redirects after sign in' do
        get :google_oauth2
        expect(response).to redirect_to(root_path)
      end

      context 'when user already exists' do
        let!(:existing_user) { create(:user, email: email, uid: '123456') }

        it 'does not create a new user' do
          expect {
            get :google_oauth2
          }.not_to change(User, :count)
        end

        it 'signs in the existing user' do
          get :google_oauth2
          expect(controller.current_user).to eq(existing_user)
        end
      end
    end

    context 'with invalid email domain' do
      let(:email) { 'test@gmail.com' }

      it 'does not create a user' do
        expect {
          get :google_oauth2
        }.not_to change(User, :count)
      end

      it 'redirects to sign in with alert' do
        get :google_oauth2
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to include('not authorized')
      end

      it 'does not sign in the user' do
        get :google_oauth2
        expect(controller.current_user).to be_nil
      end
    end
  end

  describe '#failure' do
    # Note: failure callback is handled by Devise routes
    # Testing via controller specs is not straightforward
    it 'is defined' do
      expect(controller).to respond_to(:failure)
    end
  end
end
