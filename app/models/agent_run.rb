class AgentRun < ApplicationRecord
  belongs_to :work_item

  validates :source, :external_id, presence: true

  def seconds
    return 0 unless started_at && completed_at

    (completed_at - started_at).to_i
  end
end
