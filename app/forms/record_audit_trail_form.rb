# frozen_string_literal: true

class RecordAuditTrailForm
  include ActiveModel::Model

  RECORD_TYPES = %w[frequency content avaliation grades teaching_plan lesson_plan].freeze

  attr_accessor :unity_id,
                :classroom_id,
                :teacher_id,
                :discipline_id,
                :start_at,
                :end_at,
                :school_calendar_year,
                :record_types

  validates :start_at, presence: true, date: true, timeliness: {
    on_or_before: :end_at, type: :date, on_or_before_message: I18n.t('errors.messages.on_or_before_message')
  }
  validates :end_at, presence: true, date: true, timeliness: {
    on_or_after: :start_at, type: :date, on_or_after_message: I18n.t('errors.messages.on_or_after_message')
  }
  validates :unity_id, presence: true
  validates :school_calendar_year, presence: true

  def selected_record_types
    types = Array(record_types).reject(&:blank?)
    types = RECORD_TYPES if types.empty?

    types & RECORD_TYPES
  end

  def unity
    Unity.find_by(id: unity_id)
  end
end
