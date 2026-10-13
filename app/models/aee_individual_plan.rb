# frozen_string_literal: true

class AeeIndividualPlan < ApplicationRecord
  include Audit

  audited

  belongs_to :unity
  belongs_to :classroom
  belongs_to :student
  belongs_to :teacher
  belongs_to :user
  belongs_to :school_calendar
  belongs_to :aee_case_study, optional: true
  has_many :aee_attendance_records, dependent: :nullify

  validates :unity, :classroom, :student, :teacher, :user, :school_calendar, presence: true
  validates :year, :start_on, :document_date, presence: true
  validates :characteristics, :identified_difficulties, :goals, presence: true
  validates :psychomotor_skills, :cognitive_skills, :socioemotional_skills, :linguistic_skills, presence: true
  validates :student_id, uniqueness: { scope: [:classroom_id, :year] }
  validates_date :start_on, :document_date
  validates_date :review_on, allow_blank: true
  validate :review_on_after_start_on

  before_validation :apply_age!
  before_validation :apply_defaults!, on: :create

  scope :ordered, -> { order(start_on: :desc, created_at: :desc) }
  scope :by_unity, ->(unity_id) { where(unity_id: unity_id) }
  scope :by_classroom, ->(classroom_id) { where(classroom_id: classroom_id) }
  scope :by_student_id, ->(student_id) { where(student_id: student_id) }
  scope :by_year, ->(year) { where(year: year) }

  def apply_defaults!
    apply_student_defaults!
    apply_from_case_study!
    apply_from_paee!
    self.specialized_teacher_name = teacher&.name if specialized_teacher_name.blank?
    self.document_date = Time.zone.today if document_date.blank?
  end

  def apply_age!
    return if student.blank?

    self.age = AeeCaseStudy.age_label_for(student.birth_date)
  end

  def apply_student_defaults!
    apply_age!
  end

  def apply_from_case_study!
    case_study = linked_case_study
    return if case_study.blank?

    self.aee_case_study = case_study if aee_case_study_id.blank?
    self.characteristics = case_study.potentialities_and_support if characteristics.blank?
    if identified_difficulties.blank?
      self.identified_difficulties = [
        case_study.individual_demands,
        case_study.barriers_and_context
      ].reject(&:blank?).join("\n\n")
    end
    self.strategies = case_study.accessibility_strategies if strategies.blank?
  end

  def apply_from_paee!
    paee = linked_paee
    return if paee.blank?

    detail = paee.aee_teaching_plan_detail

    assign_if_present(:characteristics, detail&.student_characteristics)
    assign_if_present(:goals, AeePrefill.strip_html(detail&.general_objectives))
    assign_if_present(:resources, detail&.resources)
    assign_if_present(:strategies, AeePrefill.strip_html(paee.methodology))
    assign_if_present(:monitoring, AeePrefill.strip_html(paee.evaluation))
    assign_if_blank(:cognitive_skills, detail&.cognitive_objectives)
    assign_if_blank(:psychomotor_skills, detail&.psychomotor_objectives)
    assign_if_blank(:socioemotional_skills, detail&.socioemotional_objectives)
  end

  def attendance_records
    return AeeAttendanceRecord.none if student_id.blank? || classroom_id.blank?

    start_date = start_on.presence || Date.new(year, 1, 1)
    end_date = review_on.presence || Time.zone.today

    AeeAttendanceRecord
      .where(classroom_id: classroom_id, student_id: student_id)
      .where(record_date: start_date..end_date)
      .order(:record_date)
  end

  def location_and_date
    city = unity&.address&.city
    state = unity&.address&.state.to_s.upcase
    place = [city, state].reject(&:blank?).join('-')
    date_label = I18n.l(document_date, format: :long) if document_date.present?

    [place.presence, date_label].compact.join(', ')
  end

  def linked_case_study
    return aee_case_study if aee_case_study.present?
    return if student_id.blank? || classroom_id.blank?

    AeeCaseStudy.find_by(student_id: student_id, classroom_id: classroom_id, year: year)
  end

  def birth_date_label
    return if student&.birth_date.blank?

    I18n.l(student.birth_date)
  end

  def linked_paee
    return if student_id.blank? || year.blank?

    TeachingPlan
      .includes(:aee_teaching_plan_detail)
      .where(student_id: student_id, year: year)
      .order(updated_at: :desc)
      .first
  end

  private

  def assign_if_present(attr, value)
    self[attr] = value if value.present?
  end

  def assign_if_blank(attr, value)
    self[attr] = value if self[attr].blank? && value.present?
  end

  def review_on_after_start_on
    return if review_on.blank? || start_on.blank?
    return if review_on >= start_on

    errors.add(:review_on, :must_be_after_start_on)
  end
end
