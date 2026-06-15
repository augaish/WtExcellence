class Company < ApplicationRecord
  has_many :company_users, dependent: :destroy
  has_many :users, through: :company_users
  has_many :capas, dependent: :nullify
  has_many :company_standards, dependent: :destroy
  has_many :folders, dependent: :destroy
  has_many :uploads, dependent: :destroy
  has_many :clause_score_caches, class_name: "ClauseScoreCache", dependent: :destroy

  validates :name, presence: true, length: { maximum: 200 }
  validates :license_seats, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :credits, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :default_locale, length: { maximum: 10 }

  scope :active, -> { where(is_active: true) }
  scope :pending, -> { where(status: "pending") }

  # Get the admin company user (admin@example.com) for this company
  def admin_company_user
    admin_user = User.find_by(email: "admin@example.com")
    return nil unless admin_user

    company_users.find_by(user: admin_user)
  end

  def pending?
    status == "pending"
  end

  def active_status?
    status == "active"
  end
end
