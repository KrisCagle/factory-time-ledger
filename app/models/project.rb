class Project < ApplicationRecord
  has_many :work_items, dependent: :nullify

  validates :repo, presence: true, uniqueness: true
  validates :name, presence: true

  def self.for_repo!(repo)
    find_or_create_by!(repo:) { |project| project.name = repo.to_s.split("/").last.to_s.titleize }
  end

  def harvest_task_id_for(activity)
    case activity.to_s
    when "development" then harvest_dev_task_id
    when "review", "qa" then harvest_qa_task_id
    when "supervision" then harvest_supervision_task_id
    end
  end

  def harvest_mapped?
    harvest_project_id.present? && [harvest_dev_task_id, harvest_qa_task_id, harvest_supervision_task_id].all?(&:present?)
  end
end
