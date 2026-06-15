class IngestionJob < ApplicationRecord
  # Validations
  validates :standard_id, presence: true
  validates :input_pdf_id, presence: true
  validates :status, presence: true, inclusion: { in: %w[queued processing completed failed] }
  validates :created_by, presence: true

  # Associations
  belongs_to :standard
  belongs_to :input_pdf, class_name: "Upload", foreign_key: "input_pdf_id"

  # Scopes
  scope :queued, -> { where(status: "queued") }
  scope :processing, -> { where(status: "processing") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :recent, -> { order(created_at: :desc) }

  # Status methods
  def queued?
    status == "queued"
  end

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def start_processing!
    update!(
      status: "processing",
      started_at: Time.current
    )
  end

  def complete!(message = nil)
    update!(
      status: "completed",
      finished_at: Time.current,
      message: message
    )
  end

  def fail!(error_message)
    update!(
      status: "failed",
      finished_at: Time.current,
      message: error_message
    )
  end

  # Duration calculation
  def duration_seconds
    return nil unless started_at
    end_time = finished_at || Time.current
    (end_time - started_at).round(2)
  end

  def duration_formatted
    return "Not started" unless started_at
    seconds = duration_seconds
    return "In progress" if seconds.nil?

    if seconds < 60
      "#{seconds}s"
    elsif seconds < 3600
      "#{(seconds / 60).round(1)}m"
    else
      "#{(seconds / 3600).round(1)}h"
    end
  end

  # Class methods
  def self.create_for_upload(input_pdf_id, created_by_id)
    create!(
      input_pdf_id: input_pdf_id,
      status: "queued",
      created_by: created_by_id
    )
  end

  def self.process_next_queued_job
    queued.order(:created_at).first
  end
end
