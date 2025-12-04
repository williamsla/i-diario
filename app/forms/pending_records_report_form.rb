class PendingRecordsReportForm
  include ActiveModel::Model

  attr_accessor :unity_id,
                :classroom_id,
                :teacher_id,
                :discipline_id,
                :start_at,
                :end_at,
                :school_calendar_year

  validates :start_at, presence: true, date: true, timeliness: {
    on_or_before: :end_at, type: :date, on_or_before_message: I18n.t('errors.messages.on_or_before_message')
  }
  validates :end_at, presence: true, date: true, timeliness: {
    on_or_after: :start_at, type: :date, on_or_after_message: I18n.t('errors.messages.on_or_after_message')
  }
  validates :unity_id, presence: true
  validates :school_calendar_year, presence: true
end

