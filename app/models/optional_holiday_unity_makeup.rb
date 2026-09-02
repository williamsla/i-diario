# frozen_string_literal: true

class OptionalHolidayUnityMakeup < ApplicationRecord
  include Audit

  audited associated_with: :optional_holiday

  belongs_to :optional_holiday
  belongs_to :unity
  belongs_to :user, optional: true

  has_enumeration_for :equivalent_weekday, with: Workdays, skip_validation: true, create_helpers: true

  validates :optional_holiday, :unity, :make_up_date, presence: true
  validates :unity_id, uniqueness: { scope: :optional_holiday_id }
  validates :equivalent_weekday, inclusion: { in: Workdays.list, allow_blank: true }
  validate :make_up_date_after_holiday_date
  before_validation :assign_equivalent_weekday_from_holiday

  scope :by_unity, ->(unity_id) { where(unity_id: unity_id) }

  private

  def make_up_date_after_holiday_date
    return if make_up_date.blank? || optional_holiday&.holiday_date.blank?
    return if make_up_date > optional_holiday.holiday_date

    errors.add(:make_up_date, :must_be_after_holiday_date)
  end

  def assign_equivalent_weekday_from_holiday
    self.equivalent_weekday = OptionalHoliday.equivalent_weekday_for_make_up(
      optional_holiday&.holiday_date,
      make_up_date
    )
  end
end
