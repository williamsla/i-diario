# frozen_string_literal: true

class AeeCaseStudy < ApplicationRecord
  include Audit

  audited

  belongs_to :unity
  belongs_to :classroom
  belongs_to :student
  belongs_to :teacher
  belongs_to :user
  belongs_to :school_calendar

  validates :unity, :classroom, :student, :teacher, :user, :school_calendar, presence: true
  validates :year, :document_date, presence: true
  validates :grade_stage, :identification, :modality, presence: true
  validates :individual_demands, :barriers_and_context, presence: true
  validates :potentialities_and_support, :accessibility_strategies, presence: true
  validates :student_id, uniqueness: { scope: [:classroom_id, :year] }
  validates_date :document_date

  before_validation :apply_age!
  before_validation :apply_identification_default!, on: :create
  before_validation :apply_regular_enrollment_fields!

  scope :ordered, -> { order(document_date: :desc, created_at: :desc) }
  scope :by_unity, ->(unity_id) { where(unity_id: unity_id) }
  scope :by_classroom, ->(classroom_id) { where(classroom_id: classroom_id) }
  scope :by_student_id, ->(student_id) { where(student_id: student_id) }
  scope :by_year, ->(year) { where(year: year) }
  scope :by_teacher, ->(teacher_id) { where(teacher_id: teacher_id) }

  def self.age_label_for(birth_date, on: Date.current)
    return if birth_date.blank?

    age = on.year - birth_date.year
    age -= 1 if on < birth_date + age.years

    I18n.t('aee_case_studies.age_label', count: age)
  end

  def apply_age!
    return if student.blank?

    self.age = self.class.age_label_for(student.birth_date)
  end

  def apply_student_defaults!
    apply_age!
    apply_identification_default!
    apply_regular_enrollment_fields!
  end

  def apply_identification_default!
    return if student.blank?

    identification_default = default_identification
    self.identification = identification_default if identification.blank? && identification_default.present?
  end

  def apply_regular_enrollment_fields!
    regular = regular_classrooms_grade
    return if regular.blank?

    self.grade_stage = regular.grade.description
    self.modality = regular.grade.course&.description
  end

  def location_and_date
    city = unity&.address&.city
    state = unity&.address&.state.to_s.upcase
    place = [city, state].reject(&:blank?).join('-')
    date_label = I18n.l(document_date, format: :long) if document_date.present?

    [place.presence, date_label].compact.join(', ')
  end

  private

  def default_identification
    return if student.blank?

    student.deficiencies.ordered.map(&:name).reject(&:blank?).uniq.join(', ')
  end

  def regular_classrooms_grade
    return if student_id.blank? || year.blank?

    StudentEnrollmentClassroom
      .joins(:student_enrollment, classrooms_grade: [:classroom, :grade])
      .where(student_enrollments: { student_id: student_id, active: IeducarBooleanState::ACTIVE })
      .where(classrooms: { year: year })
      .where('grades.description NOT ILIKE :aee AND classrooms.description NOT ILIKE :aee', aee: '%aee%')
      .order("CASE WHEN COALESCE(student_enrollment_classrooms.left_at, '') = '' THEN 0 ELSE 1 END")
      .order('student_enrollment_classrooms.joined_at DESC')
      .first
      &.classrooms_grade
  end
end
