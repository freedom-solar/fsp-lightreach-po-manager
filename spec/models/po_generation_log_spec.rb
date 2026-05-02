require 'rails_helper'

RSpec.describe PoGenerationLog, type: :model do
  describe 'associations' do
    it { should belong_to(:po_generation_job) }
  end

  describe 'validations' do
    it { should validate_presence_of(:level) }
    it { should validate_presence_of(:message) }
    it { should validate_inclusion_of(:level).in_array(%w[info success warning error]) }
  end

  describe 'scopes' do
    let(:job) { create(:po_generation_job) }
    let!(:log1) { create(:po_generation_log, po_generation_job: job, created_at: 2.minutes.ago) }
    let!(:log2) { create(:po_generation_log, po_generation_job: job, created_at: 1.minute.ago) }
    let!(:log3) { create(:po_generation_log, po_generation_job: job, created_at: Time.current) }

    describe '.ordered' do
      it 'returns logs in chronological order' do
        expect(described_class.ordered).to eq([log1, log2, log3])
      end
    end
  end

  describe 'creation' do
    let(:job) { create(:po_generation_job) }

    it 'creates a valid log with all required attributes' do
      log = described_class.create!(
        po_generation_job: job,
        level: 'info',
        message: 'Test message',
        metadata: { key: 'value' }
      )

      expect(log).to be_persisted
      expect(log.level).to eq('info')
      expect(log.message).to eq('Test message')
      expect(log.metadata).to eq({ 'key' => 'value' })
    end

    it 'allows all valid log levels' do
      %w[info success warning error].each do |level|
        log = described_class.create(
          po_generation_job: job,
          level: level,
          message: 'Test'
        )
        expect(log).to be_valid
      end
    end

    it 'rejects invalid log levels' do
      log = described_class.new(
        po_generation_job: job,
        level: 'invalid',
        message: 'Test'
      )
      expect(log).not_to be_valid
      expect(log.errors[:level]).to be_present
    end
  end

  describe 'timestamp handling' do
    it 'sets created_at automatically' do
      log = create(:po_generation_log)
      expect(log.created_at).to be_present
    end

    it 'orders logs by created_at ascending' do
      job = create(:po_generation_job)
      log1 = create(:po_generation_log, po_generation_job: job, created_at: 1.minute.ago)
      log2 = create(:po_generation_log, po_generation_job: job, created_at: Time.current)

      ordered = job.po_generation_logs.ordered
      expect(ordered.first).to eq(log1)
      expect(ordered.last).to eq(log2)
    end
  end

  describe 'message handling' do
    it 'allows long messages' do
      long_message = 'A' * 500
      log = create(:po_generation_log, message: long_message)
      expect(log.message).to eq(long_message)
    end

    it 'preserves message content exactly' do
      message_with_special_chars = "Test\nwith\nnewlines\tand\ttabs"
      log = create(:po_generation_log, message: message_with_special_chars)
      expect(log.reload.message).to eq(message_with_special_chars)
    end
  end
end
