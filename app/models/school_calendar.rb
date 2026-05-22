class SchoolCalendar < ApplicationRecord
  acts_as_copy_target

  before_validation :self_assign_to_steps
  after_create :seed_events

  audited
  has_associated_audits

  include Audit
  include Filterable

  belongs_to :unity

  has_many :steps, -> { includes(:school_calendar).ordered }, class_name: 'SchoolCalendarStep', dependent: :destroy
  has_many :classrooms, class_name: 'SchoolCalendarClassroom', dependent: :destroy
  has_many :events, class_name: 'SchoolCalendarEvent', dependent: :destroy
  has_many :absence_justifications, dependent: :restrict_with_exception
  has_many :avaliations, dependent: :restrict_with_exception
  has_many :daily_frequencies, dependent: :restrict_with_exception
  has_many :final_recovery_diary_records, dependent: :restrict_with_exception
  has_many :lesson_plans, dependent: :restrict_with_exception
  has_many :observation_diary_records, dependent: :restrict_with_exception

  accepts_nested_attributes_for :steps, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :classrooms, reject_if: :all_blank, allow_destroy: true

  validates :year, presence: true, uniqueness: { scope: :unity_id }
  validates :number_of_classes, presence: true, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 1,
    less_than_or_equal_to: 10
  }

  validates_associated :steps

  scope :by_year, lambda { |year| where(year: year) }
  scope :by_unity_id, lambda { |unity_id| where(unity_id: unity_id) }
  scope :by_unity_api_code, lambda { |unity_api_code| joins(:unity).where(unities: { api_code: unity_api_code }) }
  scope :by_school_day, lambda { |date| by_school_day(date) }
  scope :only_opened_years, -> { where(opened_year: true) }
  scope :ordered, -> { joins(:unity).order(year: :desc).order('unities.name') }

  def to_s
    "#{year}"
  end

  def school_day_checker(date, grade_id = nil, classroom_id = nil, discipline_id = nil)
    SchoolDayChecker.new(self, date, grade_id, classroom_id, discipline_id)
  end

  def school_day?(date, grade_id = nil, classroom_id = nil, discipline_id = nil)
    school_day_checker(date, grade_id, classroom_id, discipline_id).school_day?
  end

  def day_allows_entry?(date, grade_id = nil, classroom_id = nil, discipline_id = nil)
    school_day_checker(date, grade_id, classroom_id, discipline_id).day_allows_entry?
  end

  def step(date)
    steps.all.started_after_and_before(date).first
  end

  def step_by_number(step_number)
    steps.find_by(step_number: step_number)
  end

  def posting_step(date)
    steps.all.posting_date_after_and_before(date).first
  end

  def school_term_day?(school_term_type_step, date, classroom = nil)
    return false if school_term_type_step.blank?

    expected_step_number = school_term_type_step.step_number
    step = resolve_calendar_step_for_school_term(date, classroom, expected_step_number)

    return false if step.blank?
    if step.school_calendar_parent.steps.count != school_term_type_step.school_term_type.steps_number
      return true
    end

    step.step_number == expected_step_number
  end

  def resolve_calendar_step_for_school_term(date, classroom, expected_step_number)
    candidates = calendar_steps_covering_date(date, classroom)
    return if candidates.blank?

    candidates.find { |s| s.step_number == expected_step_number } || candidates.first
  end

  def calendar_steps_covering_date(date, classroom)
    if classroom.blank?
      step_record = step(date)
      return step_record ? [step_record] : []
    end

    school_calendar_classroom = classrooms.find_by(classroom_id: classroom.id)
    if school_calendar_classroom.present?
      school_calendar_classroom.classroom_steps.started_after_and_before(date).order(:step_number).to_a
    else
      steps.started_after_and_before(date).order(:step_number).to_a
    end
  end

  def first_day
    steps.reorder(start_at: :asc).first.start_at
  end

  def last_day
    steps.reorder(start_at: :desc).first.end_at
  end

  private

  def self.by_school_day(date)
    joins(:steps).where(SchoolCalendarStep.arel_table[:start_at].lteq(date.to_date))
                 .where(SchoolCalendarStep.arel_table[:end_at].gteq(date.to_date))
  end

  def self_assign_to_steps
    steps.each { |step| step.school_calendar = self }
  end

  def seed_events
    events_seeder = SchoolCalendarEventsSeeder.new(school_calendar: self)
    events_seeder.seed
  end
end
