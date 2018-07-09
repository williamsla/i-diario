class RecoveryDiaryRecord < ActiveRecord::Base
  include Audit

  acts_as_copy_target

  audited
  has_associated_audits

  belongs_to :unity
  belongs_to :classroom, -> { includes(:exam_rule) }
  belongs_to :discipline

  has_many :students, -> { includes(:student).ordered },
    class_name: 'RecoveryDiaryRecordStudent',
    dependent: :destroy

  accepts_nested_attributes_for :students, allow_destroy: true

  has_one :school_term_recovery_diary_record
  has_one :final_recovery_diary_record
  has_one :avaliation_recovery_diary_record

  scope :by_classroom_id, lambda { |classroom_id| where(classroom_id: classroom_id) }
  scope :by_discipline_id, lambda { |discipline_id| where(discipline_id: discipline_id) }
  scope :by_student_id, lambda { |student_id| joins(:students).where(recovery_diary_record_students: { student_id: student_id }) }

  validates_date :recorded_at
  validates :unity, presence: true
  validates :classroom, presence: true
  validates :discipline, presence: true
  validates :recorded_at, presence: true, school_calendar_day: true

  validate :at_least_one_assigned_student
  validate :recorded_at_must_be_less_than_or_equal_to_today

  before_validation :self_assign_to_students

  def school_calendar
    CurrentSchoolCalendarFetcher.new(unity, classroom).fetch
  end

  def test_date
    recorded_at
  end

  private

  def at_least_one_assigned_student
    errors.add(:students, :at_least_one_assigned_student) if students.reject(&:marked_for_destruction?).empty?
  end

  def recorded_at_must_be_less_than_or_equal_to_today
    return unless recorded_at

    if recorded_at > Time.zone.today
      errors.add(:recorded_at, :recorded_at_must_be_less_than_or_equal_to_today)
    end
  end

  def self_assign_to_students
    students.each { |student| student.recovery_diary_record = self }
  end
end
