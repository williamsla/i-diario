# frozen_string_literal: true

class AeeAttendanceRecord < ApplicationRecord
  include Audit

  audited

  belongs_to :unity
  belongs_to :classroom
  belongs_to :student
  belongs_to :teacher
  belongs_to :user
  belongs_to :school_calendar
  belongs_to :aee_individual_plan, optional: true

  validates :unity, :classroom, :student, :teacher, :user, :school_calendar, presence: true
  validates :year, :record_date, :activities_developed, presence: true
  validates :student_id, uniqueness: { scope: [:classroom_id, :record_date] }
  validates_date :record_date

  before_validation :apply_defaults!, on: :create

  scope :ordered, -> { order(record_date: :desc, created_at: :desc) }
  scope :by_unity, ->(unity_id) { where(unity_id: unity_id) }
  scope :by_classroom, ->(classroom_id) { where(classroom_id: classroom_id) }
  scope :by_student_id, ->(student_id) { where(student_id: student_id) }
  scope :by_year, ->(year) { where(year: year) }
  scope :by_record_date, ->(date) { where(record_date: date) }

  def apply_defaults!
    apply_from_pei!
    apply_from_paee!
  end

  def apply_from_pei!
    pei = linked_pei
    return if pei.blank?

    self.aee_individual_plan = pei if aee_individual_plan_id.blank?
    self.session_objectives = pei.goals if session_objectives.blank?
  end

  def apply_from_paee!
    return if duration.present?

    detail = linked_pei&.linked_paee&.aee_teaching_plan_detail
    self.duration = detail.attendance_duration if detail&.attendance_duration.present?
  end

  def linked_pei
    return aee_individual_plan if aee_individual_plan.present?
    return if student_id.blank? || classroom_id.blank?

    AeeIndividualPlan.find_by(student_id: student_id, classroom_id: classroom_id, year: year)
  end

  def to_s
    session_focus.presence || student.to_s
  end
end
