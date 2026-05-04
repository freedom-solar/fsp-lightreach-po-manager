class PoGenerationJob < ApplicationRecord
  belongs_to :user
  has_many :po_generation_logs, dependent: :destroy

  validates :job_type, inclusion: { in: %w[region batch single] }
  validates :status, inclusion: { in: %w[pending running completed failed] }

  scope :running, -> { where(status: 'running') }
  scope :pending, -> { where(status: 'pending') }
  scope :completed, -> { where(status: 'completed') }

  # Check if PO generation is running for a region
  def self.running_for_region?(region)
    running.where(region: region).exists?
  end

  # Get all currently locked project IDs
  def self.locked_project_ids
    running.where.not(project_ids: nil).pluck(:project_ids).flatten.uniq
  end

  # Atomic lock acquisition
  def acquire_lock!(worker_id)
    update_columns(
      locked_at: Time.current,
      locked_by: worker_id,
      status: 'running',
      started_at: Time.current
    )
  end

  def release_lock!
    update_columns(locked_at: nil, locked_by: nil)
  end

  def running?
    status == 'running'
  end

  def pending?
    status == 'pending'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def cancelled?
    failed? && error_message == 'Job cancelled by user'
  end
end
