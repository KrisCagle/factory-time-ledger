class Person < ApplicationRecord
  has_many :attention_spans, dependent: :destroy
  has_many :time_drafts, dependent: :destroy

  validates :name, :email, presence: true
  validates :email, uniqueness: { case_sensitive: false }

  before_validation { self.email = email.to_s.strip.downcase }

  def self.for_email!(email, name: nil)
    find_or_create_by!(email: email.to_s.strip.downcase) do |person|
      person.name = name.presence || email.to_s.split("@").first.to_s.titleize
    end
  end
end
