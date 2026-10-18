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

  has_many :aee_individual_plans, dependent: :nullify

  validates :unity, :classroom, :student, :teacher, :user, :school_calendar, presence: true
  validates :year, :document_date, presence: true
  validates :grade_stage, :identification, :modality, presence: true
  validates :individual_demands, :barriers_and_context, presence: true
  validates :potentialities_and_support, :accessibility_strategies, presence: true
  validates :student_id, uniqueness: { scope: [:classroom_id, :year] }
  validates_date :document_date

  before_validation :apply_age!
  before_validation :apply_student_defaults!, on: :create

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
    return if student.blank?

    apply_age!

    identification_default = default_identification
    self.identification = identification_default if identification.blank? && identification_default.present?
    self.grade_stage = classroom_grade_description if grade_stage.blank?
    self.modality = classroom_course_description if modality.blank?
  end

  def location_and_date
    city = unity&.address&.city
    state = unity&.address&.state.to_s.upcase
    place = [city, state].reject(&:blank?).join('-')
    date_label = I18n.l(document_date, format: :long) if document_date.present?

    [place.presence, date_label].compact.join(', ')
  end

  def self.latest_for_aee(student:, unity:, year:)
    return if student.blank? || unity.blank? || year.blank?

    where(student_id: student.id, unity_id: unity.id, year: year)
      .includes(classroom: :grades)
      .ordered
      .detect { |study| study.classroom&.aee? }
  end

  def self.consultation_payload_for(student:, unity:, year:)
    study = latest_for_aee(student: student, unity: unity, year: year)
    return { present: false } if study.blank?

    study.consultation_payload
  end

  def consultation_payload
    {
      present: true,
      summary: consultation_summary,
      sections: consultation_sections
    }
  end

  def consultation_summary
    date_label = I18n.l(document_date) if document_date.present?

    [date_label, classroom&.to_s].reject(&:blank?).join(' — ')
  end

  def consultation_sections
    %i[
      identification
      individual_demands
      barriers_and_context
      potentialities_and_support
      accessibility_strategies
      final_considerations
    ].map { |attribute| { label: self.class.human_attribute_name(attribute), text: public_send(attribute).to_s.strip } }
      .select { |section| section[:text].present? }
  end

  private

  def default_identification
    return if student.blank?

    student.deficiencies.ordered.map(&:name).reject(&:blank?).join(', ')
  end

  def classroom_grade_description
    classroom&.grades&.map(&:description)&.uniq&.join(', ')
  end

  def classroom_course_description
    classroom&.courses&.compact&.map(&:description)&.uniq&.join(', ')
  end
end
