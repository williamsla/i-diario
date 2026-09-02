# frozen_string_literal: true

class OptionalHoliday < ApplicationRecord
  include Audit

  HOLIDAY_LEGEND = 'P'.freeze
  MAKEUP_LABEL_I18N = 'optional_holidays.makeup_label'.freeze

  audited
  has_associated_audits

  belongs_to :user

  has_many :optional_holiday_attachments, dependent: :destroy
  has_many :optional_holiday_unity_makeups, dependent: :destroy
  has_many :school_calendar_events, dependent: :destroy

  accepts_nested_attributes_for :optional_holiday_attachments, allow_destroy: true

  has_enumeration_for :makeup_scope, with: OptionalHolidayMakeupScope, create_helpers: true
  has_enumeration_for :equivalent_weekday, with: Workdays, skip_validation: true, create_helpers: true

  validates_date :holiday_date
  validates_date :make_up_date, allow_blank: true
  validates :year, :holiday_date, :description, :makeup_scope, :user, presence: true
  validates :holiday_date, uniqueness: { scope: :year }
  validates :periods, presence: true
  validates :equivalent_weekday, inclusion: { in: Workdays.list, allow_blank: true }
  validate :make_up_date_after_holiday_date
  validate :municipal_make_up_presence_when_informed
  before_validation :assign_equivalent_weekday_from_holiday

  scope :ordered, -> { order(holiday_date: :desc) }
  scope :by_year, ->(year) { where(year: year.to_i) }
  scope :by_holiday_date, ->(date) { where(holiday_date: date) }
  scope :by_holiday_date_between, ->(start_at, end_at) {
    where(holiday_date: start_at.to_date..end_at.to_date)
  }
  scope :by_description, lambda { |description|
    where('unaccent(optional_holidays.description) ILIKE unaccent(?)', "%#{description}%")
  }

  def to_s
    description
  end

  def periods=(value)
    arr = case value
          when String then value.split(',').map(&:strip).reject(&:blank?)
          when Array then value.map(&:to_s).reject(&:blank?)
          else value
          end
    write_attribute(:periods, arr.presence&.sort || [])
  end

  def effective_periods
    Array(self[:periods]).map(&:to_s)
  end

  def makeup_scope_municipal?
    makeup_scope == OptionalHolidayMakeupScope::MUNICIPAL
  end

  def makeup_scope_by_school?
    makeup_scope == OptionalHolidayMakeupScope::BY_SCHOOL
  end

  def pending_make_up?
    makeup_scope_municipal? && make_up_date.blank?
  end

  def make_up_date_for(unity_id)
    return make_up_date if makeup_scope_municipal?

    optional_holiday_unity_makeups.detect { |makeup| makeup.unity_id == unity_id.to_i }&.make_up_date
  end

  def equivalent_weekday_for(unity_id)
    return equivalent_weekday if makeup_scope_municipal?

    optional_holiday_unity_makeups.detect { |makeup| makeup.unity_id == unity_id.to_i }&.equivalent_weekday
  end

  def pending_make_up_for?(unity_id)
    make_up_date_for(unity_id).blank?
  end

  def unity_makeup_for(unity_id)
    optional_holiday_unity_makeups.detect { |makeup| makeup.unity_id == unity_id.to_i } ||
      optional_holiday_unity_makeups.build(unity_id: unity_id)
  end

  def applies_to_period?(period)
    return true if effective_periods.blank?
    return false if period.blank?

    requested = period.to_s
    return true if effective_periods.include?(requested)

    if requested == Periods::FULL
      effective_periods.include?(Periods::FULL) || (effective_periods & %w[1 2 3]).size >= 3
    else
      false
    end
  end

  def self.blocks_frequency?(classroom:, date:, period: nil, unity_id: nil)
    classroom = classroom.is_a?(Classroom) ? classroom : Classroom.find_by(id: classroom)
    return false if classroom.blank? || date.blank?

    period_to_match = period.presence || classroom.period
    unity_id ||= classroom.unity_id

    by_year(classroom.year.to_i)
      .by_holiday_date(date.to_date)
      .any? { |holiday| holiday.applies_to_period?(period_to_match) && holiday_applies_to_unity?(holiday, unity_id) }
  end

  def self.holiday_dates_for(classroom:, start_date:, end_date:, period: nil, unity_id: nil)
    classroom = classroom.is_a?(Classroom) ? classroom : Classroom.find_by(id: classroom)
    return Set.new if classroom.blank?

    period_to_match = period.presence || classroom.period
    unity_id ||= classroom.unity_id

    by_year(classroom.year.to_i)
      .by_holiday_date_between(start_date, end_date)
      .select { |holiday| holiday.applies_to_period?(period_to_match) && holiday_applies_to_unity?(holiday, unity_id) }
      .map { |holiday| holiday.holiday_date.to_date }
      .to_set
  end

  def self.make_up_dates_for(classroom:, start_date:, end_date:, period: nil, unity_id: nil)
    classroom = classroom.is_a?(Classroom) ? classroom : Classroom.find_by(id: classroom)
    return Set.new if classroom.blank?

    period_to_match = period.presence || classroom.period
    unity_id ||= classroom.unity_id
    start_at = start_date.to_date
    end_at = end_date.to_date

    by_year(classroom.year.to_i).includes(:optional_holiday_unity_makeups).each_with_object(Set.new) do |holiday, dates|
      next unless holiday.applies_to_period?(period_to_match)
      next unless holiday_applies_to_unity?(holiday, unity_id)

      makeup_date = holiday.make_up_date_for(unity_id)
      next if makeup_date.blank?

      makeup_date = makeup_date.to_date
      dates << makeup_date if makeup_date.between?(start_at, end_at)
    end
  end

  def self.make_up_on_date?(classroom:, date:, period: nil, unity_id: nil)
    classroom = classroom.is_a?(Classroom) ? classroom : Classroom.find_by(id: classroom)
    return false if classroom.blank? || date.blank?

    period_to_match = period.presence || classroom.period
    unity_id ||= classroom.unity_id
    date = date.to_date

    by_year(classroom.year.to_i).includes(:optional_holiday_unity_makeups).any? do |holiday|
      next false unless holiday.applies_to_period?(period_to_match)
      next false unless holiday_applies_to_unity?(holiday, unity_id)

      holiday.make_up_date_for(unity_id).to_s == date.to_s
    end
  end

  def self.make_up_holidays_on_date(classroom:, date:, period: nil, unity_id: nil)
    classroom = classroom.is_a?(Classroom) ? classroom : Classroom.find_by(id: classroom)
    return [] if classroom.blank? || date.blank?

    period_to_match = period.presence || classroom.period
    unity_id ||= classroom.unity_id
    date = date.to_date

    by_year(classroom.year.to_i).includes(:optional_holiday_unity_makeups).select do |holiday|
      holiday.applies_to_period?(period_to_match) &&
        holiday_applies_to_unity?(holiday, unity_id) &&
        holiday.make_up_date_for(unity_id).to_s == date.to_s
    end
  end

  def self.make_up_lessons_count_for(classroom:, date:, count_lessons_on_date: nil, period: nil, unity_id: nil)
    holidays = make_up_holidays_on_date(
      classroom: classroom,
      date: date,
      period: period,
      unity_id: unity_id
    )
    return 0 if holidays.blank?

    holidays.sum do |holiday|
      if count_lessons_on_date
        count = count_lessons_on_date.call(holiday.holiday_date).to_i
        count.positive? ? count : 1
      else
        1
      end
    end
  end

  def self.makeup_label
    I18n.t(MAKEUP_LABEL_I18N)
  end

  def self.format_pending_date(date, makeup_dates = [])
    return if date.blank?

    formatted = date.respond_to?(:strftime) ? date.strftime('%d/%m/%Y') : date.to_s
    return formatted if makeup_dates.blank?

    date_value = date.respond_to?(:to_date) ? date.to_date : Date.parse(date.to_s)
    makeup_set = Array(makeup_dates).map { |makeup_date|
      makeup_date.respond_to?(:to_date) ? makeup_date.to_date : Date.parse(makeup_date.to_s)
    }.to_set

    makeup_set.include?(date_value) ? "#{formatted} (#{makeup_label})" : formatted
  end

  def self.equivalent_weekday_for_make_up(holiday_date, make_up_date)
    return if holiday_date.blank? || make_up_date.blank?
    return unless make_up_date.to_date.saturday?

    {
      1 => Workdays::MONDAY,
      2 => Workdays::TUESDAY,
      3 => Workdays::WEDNESDAY,
      4 => Workdays::THURSDAY,
      5 => Workdays::FRIDAY
    }[holiday_date.to_date.wday]
  end

  def self.holiday_applies_to_unity?(_holiday, _unity_id)
    true
  end
  private_class_method :holiday_applies_to_unity?

  private

  def make_up_date_after_holiday_date
    return if make_up_date.blank? || holiday_date.blank?
    return if make_up_date > holiday_date

    errors.add(:make_up_date, :must_be_after_holiday_date)
  end

  def assign_equivalent_weekday_from_holiday
    self.equivalent_weekday = self.class.equivalent_weekday_for_make_up(holiday_date, make_up_date)
  end

  def municipal_make_up_presence_when_informed
    return unless makeup_scope_by_school?

    self.make_up_date = nil
    self.equivalent_weekday = nil
  end
end
