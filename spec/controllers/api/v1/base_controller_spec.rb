require 'rails_helper'

RSpec.describe Api::V1::BaseController, type: :controller do
  controller(Api::V1::BaseController) do
    def test_render_success
      render_success({ message: 'Success' }, status: :created)
    end

    def test_render_error
      render_error('Something went wrong', status: :bad_request)
    end

    def test_render_error_with_errors
      render_error('Validation failed', status: :unprocessable_entity, errors: { email: ['is invalid'] })
    end

    def test_not_found
      raise ActiveRecord::RecordNotFound, 'Record not found'
    end

    def test_record_invalid
      user = User.new
      user.valid?
      raise ActiveRecord::RecordInvalid.new(user)
    end
  end

  let(:user) { create(:user) }

  before do
    routes.draw do
      get 'test_render_success' => 'api/v1/base#test_render_success'
      get 'test_render_error' => 'api/v1/base#test_render_error'
      get 'test_render_error_with_errors' => 'api/v1/base#test_render_error_with_errors'
      get 'test_not_found' => 'api/v1/base#test_not_found'
      get 'test_record_invalid' => 'api/v1/base#test_record_invalid'
    end
  end

  describe 'authentication' do
    context 'when user is not authenticated' do
      it 'returns unauthorized' do
        get :test_render_success
        expect(response).to have_http_status(:found)
      end
    end
  end

  describe '#render_success' do
    before { sign_in user }

    it 'renders success response with data' do
      get :test_render_success
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['message']).to eq('Success')
    end
  end

  describe '#render_error' do
    before { sign_in user }

    it 'renders error response with message' do
      get :test_render_error
      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
      expect(json['error']).to eq('Something went wrong')
    end

    it 'includes errors when provided' do
      get :test_render_error_with_errors
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
      expect(json['error']).to eq('Validation failed')
      expect(json['errors']).to eq({ 'email' => ['is invalid'] })
    end
  end

  describe 'error handling' do
    before { sign_in user }

    describe 'ActiveRecord::RecordNotFound' do
      it 'returns not found response' do
        get :test_not_found
        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Record not found')
      end
    end

    describe 'ActiveRecord::RecordInvalid' do
      it 'returns unprocessable entity response' do
        get :test_record_invalid
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('Validation failed')
      end
    end
  end
end
