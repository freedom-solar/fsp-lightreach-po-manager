require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should have_many(:po_generation_jobs).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
  end

  describe '.from_google' do
    let(:email) { 'test@gofreedompower.com' }
    let(:uid) { 'google_123' }
    let(:full_name) { 'Test User' }

    context 'with valid @gofreedompower.com email' do
      it 'creates a new user' do
        expect {
          User.from_google(uid: uid, email: email, full_name: full_name)
        }.to change(User, :count).by(1)
      end

      it 'returns the created user' do
        user = User.from_google(uid: uid, email: email, full_name: full_name)
        expect(user).to be_persisted
        expect(user.email).to eq(email)
        expect(user.uid).to eq(uid)
        expect(user.full_name).to eq(full_name)
      end

      it 'finds existing user instead of creating duplicate' do
        existing_user = create(:user, email: email, uid: uid)
        user = User.from_google(uid: uid, email: email, full_name: full_name)
        expect(user.id).to eq(existing_user.id)
      end
    end

    context 'with invalid email domain' do
      let(:invalid_email) { 'test@gmail.com' }

      it 'returns nil' do
        user = User.from_google(uid: uid, email: invalid_email, full_name: full_name)
        expect(user).to be_nil
      end

      it 'does not create a user' do
        expect {
          User.from_google(uid: uid, email: invalid_email, full_name: full_name)
        }.not_to change(User, :count)
      end
    end

    context 'with subdomain in email' do
      let(:subdomain_email) { 'test@subdomain.gofreedompower.com' }

      it 'rejects subdomain emails' do
        user = User.from_google(uid: uid, email: subdomain_email, full_name: full_name)
        expect(user).to be_nil
      end
    end

    context 'with edge case emails' do
      it 'handles uppercase domain' do
        user = User.from_google(uid: uid, email: 'test@GOFREEDOMPOWER.COM', full_name: full_name)
        expect(user).to be_nil # Regex is case-sensitive
      end

      it 'handles email with special characters' do
        user = User.from_google(uid: uid, email: 'test+tag@gofreedompower.com', full_name: full_name)
        expect(user).to be_persisted
      end
    end
  end

  describe 'dependent destroy' do
    it 'destroys associated po_generation_jobs when user is destroyed' do
      user = create(:user)
      create(:po_generation_job, user: user)
      create(:po_generation_job, user: user)

      expect { user.destroy }.to change(PoGenerationJob, :count).by(-2)
    end

    it 'also destroys nested po_generation_logs through jobs' do
      user = create(:user)
      job = create(:po_generation_job, user: user)
      create(:po_generation_log, po_generation_job: job)
      create(:po_generation_log, po_generation_job: job)

      expect { user.destroy }.to change(PoGenerationLog, :count).by(-2)
    end
  end

  describe 'email normalization' do
    it 'stores email in lowercase' do
      email = 'TEST@gofreedompower.com'
      user = User.from_google(uid: 'uid123', email: email, full_name: 'Test')
      expect(user.email).to eq(email.downcase)
    end

    it 'trims whitespace from email automatically' do
      user = create(:user, email: '  test@example.com  ')
      expect(user.email).to eq('test@example.com')
    end
  end

  describe 'uniqueness validation' do
    let(:existing_user) { create(:user, email: 'test@example.com') }

    it 'prevents duplicate emails' do
      duplicate_user = User.new(email: existing_user.email)
      expect(duplicate_user).not_to be_valid
      expect(duplicate_user.errors[:email]).to include('has already been taken')
    end

    it 'is case insensitive for email uniqueness' do
      duplicate_user = User.new(email: existing_user.email.upcase)
      expect(duplicate_user).not_to be_valid
    end
  end
end
