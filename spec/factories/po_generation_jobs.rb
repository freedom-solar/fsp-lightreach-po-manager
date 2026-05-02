FactoryBot.define do
  factory :po_generation_job do
    association :user
    job_type { 'single' }
    status { 'pending' }
    total_projects { 1 }
    successful_pos { 0 }
    failed_pos { 0 }

    trait :single_job do
      job_type { 'single' }
      project_ids { ['SF-001'] }
      total_projects { 1 }
    end

    trait :region_job do
      job_type { 'region' }
      region { 'NorCal' }
      total_projects { 5 }
    end

    trait :batch_job do
      job_type { 'batch' }
      project_ids { %w[proj_1 proj_2 proj_3] }
      total_projects { 3 }
    end

    trait :running do
      status { 'running' }
      started_at { Time.current }
      locked_at { Time.current }
      locked_by { 'worker_123' }
    end

    trait :completed do
      status { 'completed' }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      successful_pos { 1 }
    end

    trait :failed do
      status { 'failed' }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      failed_pos { 1 }
      error_message { 'Something went wrong' }
    end

    trait :completed_batch do
      job_type { 'batch' }
      status { 'completed' }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      total_projects { 2 }
      successful_pos { 2 }
      po_results { [] }
    end
  end
end
