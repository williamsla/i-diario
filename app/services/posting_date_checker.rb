class PostingDateChecker
  ERROR_MARKER = 'fora das datas de lançamento da etapa'.freeze
  CLOSED_YEAR_MARKER = 'ano letivo está fechado'.freeze

  def initialize(classroom, record_date)
    @classroom = classroom
    @record_date = record_date
  end

  def check
    return true unless User.current
    return true if thread_origin_type_is_api?
    return false if unrestricted_posting_on_closed_year?
    return true if date_allows_entry_outside_steps?
    return false unless step
    return true if User.current.posting_without_date_restrictions?
    return false if step_posting_not_started?
    return true if User.current.can_change?(Features::IEDUCAR_API_EXAM_POSTING_WITHOUT_RESTRICTIONS)

    current_between_step? && record_date_between_step?
  end

  def not_allowed_message
    return I18n.t('errors.messages.school_year_closed') if @closed_school_year

    I18n.t(
      'errors.messages.not_allowed_to_post_in_date',
      start_date: format_date(step.try(:start_date_for_posting)),
      end_date: format_date(step.try(:end_date_for_posting))
    )
  end

  def self.not_allowed_error?(messages)
    Array(messages).flatten.any? { |message| posting_blocked_message?(message) }
  end

  def self.find_error(messages)
    Array(messages).flatten.find { |message| posting_blocked_message?(message) }
  end

  def self.posting_blocked_message?(message)
    text = message.to_s
    text.include?(ERROR_MARKER) || text.include?(CLOSED_YEAR_MARKER)
  end

  private

  def format_date(date)
    date.present? ? I18n.l(date) : '—'
  end

  def record_date_between_step?
    (step.start_date_for_posting..step.end_date_for_posting) === @record_date
  end

  def current_between_step?
    (step.start_date_for_posting..step.end_date_for_posting) === Time.zone.today
  end

  def step
    @step ||= StepsFetcher.new(@classroom).step_by_date(@record_date)
  end

  def date_allows_entry_outside_steps?
    return false if step.present?

    school_calendar = StepsFetcher.new(@classroom).school_calendar
    return false if school_calendar.blank?

    school_calendar.day_allows_entry?(@record_date, nil, @classroom.id, nil)
  end

  def thread_origin_type_is_api?
    OriginTypes::API_V2 == Thread.current[:origin_type]
  end

  def unrestricted_posting_on_closed_year?
    return false unless User.current.posting_without_date_restrictions?
    return false if school_year_opened?

    @closed_school_year = true
  end

  def school_year_opened?
    StepsFetcher.new(@classroom).school_calendar&.opened_year?
  end

  def step_posting_not_started?
    return false if step.start_date_for_posting.blank?

    Time.zone.today < step.start_date_for_posting
  end
end
