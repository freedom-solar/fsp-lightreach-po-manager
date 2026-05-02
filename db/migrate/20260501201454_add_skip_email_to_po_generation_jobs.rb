class AddSkipEmailToPoGenerationJobs < ActiveRecord::Migration[7.2]
  def change
    add_column :po_generation_jobs, :skip_email, :boolean, default: false
  end
end
