# One work item in another system (for now, Scarif) that the ledger has read.
class ExternalRecord < ApplicationRecord
  belongs_to :work_item, optional: true

  validates :source, :external_id, presence: true
end
