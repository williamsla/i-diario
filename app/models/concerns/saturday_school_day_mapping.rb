# frozen_string_literal: true

module SaturdaySchoolDayMapping
  extend ActiveSupport::Concern

  included do
    has_enumeration_for :equivalent_weekday, with: Workdays, skip_validation: true

    validates :equivalent_weekday, inclusion: { in: Workdays.list, allow_blank: true }
    validate :equivalent_weekday_for_saturday_school_day
  end

  def extra_school_event?
    [EventTypes::EXTRA_SCHOOL, EventTypes::EXTRA_SCHOOL_WITHOUT_FREQUENCY].include?(event_type)
  end

  def saturday_school_day?
    return false if start_date.blank? || end_date.blank?

    (start_date..end_date).any?(&:saturday?)
  end

  def requires_equivalent_weekday?
    extra_school_event? && saturday_school_day?
  end

  private

  def equivalent_weekday_for_saturday_school_day
    return unless requires_equivalent_weekday?

    saturdays = (start_date..end_date).select(&:saturday?)

    if saturdays.many? || start_date != end_date
      errors.add(:start_date, :saturday_school_day_requires_single_date)
      errors.add(:end_date, :saturday_school_day_requires_single_date)
    end

    errors.add(:equivalent_weekday, :blank) if equivalent_weekday.blank?
  end
end
