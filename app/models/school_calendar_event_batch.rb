class SchoolCalendarEventBatch < ApplicationRecord
  audited

  include SaturdaySchoolDayMapping

  has_many :school_calendar_events, dependent: :nullify, foreign_key: 'batch_id'

  has_enumeration_for :event_type, with: EventTypes
  has_enumeration_for :batch_status, with: BatchStatus, create_helpers: true

  validates :description, :event_type, :start_date, :end_date, :year, :periods, presence: true
  validates :legend, presence: true, exclusion: { in: %w(F f N n .) }, if: :should_validate_legend?
  validates :start_date, presence: true, date: true, timeliness: {
    on_or_before: :end_date,
    type: :date,
    on_or_before_message: :on_or_before_message
  }
  validates :end_date, presence: true, date: true, timeliness: {
    on_or_after: :start_date,
    type: :date,
    on_or_after_message: :on_or_after_message
  }

  scope :ordered, -> { order(:start_date) }
  scope :by_year, ->(year) { where(year: year) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :by_status, ->(status) { where(batch_status: status) }
  scope :by_date, lambda { |date|
    where(
      '? BETWEEN school_calendar_event_batches.start_date AND school_calendar_event_batches.end_date',
      date.to_date
    )
  }
  scope :by_description, lambda { |description|
    where('unaccent(school_calendar_event_batches.description) ILIKE unaccent(?)', "%#{description}%")
  }
  scope :stuck_started, lambda {
    where(batch_status: BatchStatus::STARTED).where('updated_at < ?', 1.minute.ago)
  }

  def self.resolve_stuck_batches!
    pending_create_ids = []

    stuck_started.find_each do |batch|
      begin
        if batch.school_calendar_events.exists?
          batch.mark_as_completed!
        elsif batch.touched_after_create?
          batch.destroy!
        else
          pending_create_ids << batch.id
        end
      rescue StandardError => error
        Rails.logger.error("Erro ao encerrar evento em lote #{batch.id}: #{error.class} - #{error.message}")
        batch.mark_with_error!(error.message) if batch.persisted? && !batch.destroyed?
      end
    end

    pending_create_ids
  end

  def mark_with_error!(message)
    update_columns(
      batch_status: BatchStatus::ERROR,
      error_message: message.to_s.truncate(255),
      updated_at: Time.current
    )
  end

  def touched_after_create?
    updated_at.present? && created_at.present? && updated_at > created_at + 2.seconds
  end

  def mark_as_completed!
    update_columns(
      batch_status: BatchStatus::COMPLETED,
      error_message: nil,
      updated_at: Time.current
    )
  end

  def duration
    "#{I18n.l(start_date)} à #{I18n.l(end_date)}"
  end

  def should_validate_legend?
    [EventTypes::EXTRA_SCHOOL, EventTypes::NO_SCHOOL_WITH_FREQUENCY].exclude?(event_type)
  end
end
