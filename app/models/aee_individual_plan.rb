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
  has_many :aee_individual_plan_disciplines, dependent: :destroy
  has_many :disciplines, through: :aee_individual_plan_disciplines
  has_many :aee_attendance_records, dependent: :nullify

  has_enumeration_for :origin, with: AeeIndividualPlanOrigins, create_helpers: true, create_scopes: true

  validates :unity, :classroom, :student, :teacher, :user, :school_calendar, :origin, presence: true
  validates :year, :start_on, :document_date, presence: true
  validates :characteristics, :identified_difficulties, :goals, presence: true
  validates :psychomotor_skills, :cognitive_skills, :socioemotional_skills, :linguistic_skills, presence: true
  validates :student_id, uniqueness: { scope: [:classroom_id, :year] }, if: :aee?
  validates :student_id, uniqueness: { scope: [:classroom_id, :year, :teacher_id] }, if: :regular?
  validates_date :start_on, :document_date
  validates_date :review_on, allow_blank: true
  validate :review_on_after_start_on
  validate :disciplines_match_teacher_links

  before_validation :apply_age!
  before_validation :clear_disciplines_unless_regular
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
    if aee?
      self.specialized_teacher_name = teacher&.name if specialized_teacher_name.blank?
    elsif regular?
      self.regular_teacher_name = teacher&.name if regular_teacher_name.blank?
    end
    self.document_date = Time.zone.today if document_date.blank?
  end

  def context_label
    return origin_humanize unless regular?

    names = disciplines.map(&:to_s).reject(&:blank?).sort.join(', ')
    return origin_humanize if names.blank?

    "#{origin_humanize} — #{names}"
  end

  def owned_by?(user)
    context = self.class.ownership_context(user)
    return false if context.blank?
    return false if year != user.current_school_year
    return false if unity_id != user.current_unity_id
    return false if classroom_id != context[:classroom].id
    return false if origin != context[:origin]
    return true if aee?

    teacher_id.present? && teacher_id == user.current_teacher&.id
  end

  def self.ownership_context(user)
    classroom = user&.classroom
    return if classroom.blank? || user.current_school_year.blank?

    if classroom.aee?
      { origin: AeeIndividualPlanOrigins::AEE, classroom: classroom }
    elsif user.current_teacher.present?
      { origin: AeeIndividualPlanOrigins::REGULAR, classroom: classroom }
    end
  end

  def self.owned_record_for(user, student_id)
    return if student_id.blank?

    context = ownership_context(user)
    if context.blank? || (context[:origin] == AeeIndividualPlanOrigins::REGULAR && user.current_teacher.blank?)
      return
    end

    scope = where(
      student_id: student_id,
      classroom_id: context[:classroom].id,
      year: user.current_school_year,
      unity_id: user.current_unity_id,
      origin: context[:origin]
    )
    scope = scope.where(teacher_id: user.current_teacher.id) if context[:origin] == AeeIndividualPlanOrigins::REGULAR
    scope.first
  end

  def self.registration_open_for?(user)
    classroom = user&.classroom
    return false if classroom.blank?
    return true if classroom.aee?
    return false if linked_disciplines_for(user).blank?

    enrolled_student_ids_for(user).any?
  end

  def self.linked_disciplines_for(user)
    classroom = user&.classroom
    teacher = user&.current_teacher
    if classroom.blank? || classroom.aee? || teacher.blank? || user.current_school_year.blank?
      return Discipline.none
    end

    discipline_ids = TeacherDisciplineClassroom
      .by_teacher_id(teacher.id)
      .by_classroom(classroom)
      .by_year(user.current_school_year)
      .distinct
      .pluck(:discipline_id)

    Discipline.where(id: discipline_ids).ordered
  end

  def self.visible_for(user)
    classroom = user&.classroom
    return none if classroom.blank? || user.current_school_year.blank? || user.current_unity_id.blank?

    student_ids = enrolled_student_ids_for(user)
    return none if student_ids.blank?

    scope = where(unity_id: user.current_unity_id, year: user.current_school_year, student_id: student_ids)
    return scope if classroom.aee?

    scope.where(
      '(origin = ? AND classroom_id = ?) OR origin = ?',
      AeeIndividualPlanOrigins::REGULAR,
      classroom.id,
      AeeIndividualPlanOrigins::AEE
    )
  end

  # Usado pelo menu em toda página. Só precisa saber se existe aluno com regra
  # diferenciada; não monta a lista de matrículas de cada disciplina.
  def self.differentiated_student_enrolled_for?(user)
    classroom = user&.classroom
    return false if classroom.blank?
    return false unless teacher_allocated_in_classroom?(user, classroom)

    StudentEnrollment
      .active
      .joins(:student, student_enrollment_classrooms: :classrooms_grade)
      .where(classrooms_grades: { classroom_id: classroom.id })
      .where(students: { uses_differentiated_exam_rule: true })
      .exists?
  end

  def self.enrolled_student_ids_for(user)
    classroom = user&.classroom
    return [] if classroom.blank?

    student_ids =
      if classroom.aee?
        student_ids_from_enrollments(classroom, user.discipline)
      else
        disciplines = linked_disciplines_for(user)
        return [] if disciplines.blank?

        disciplines.flat_map { |discipline| student_ids_from_enrollments(classroom, discipline) }.uniq
      end

    return student_ids if classroom.aee?

    Student.where(id: student_ids, uses_differentiated_exam_rule: true).pluck(:id)
  end

  def self.teacher_allocated_in_classroom?(user, classroom)
    teacher = user.current_teacher
    return false if teacher.blank? || user.current_school_year.blank?

    TeacherDisciplineClassroom.by_teacher_id(teacher.id)
                              .by_classroom(classroom)
                              .by_year(user.current_school_year)
                              .exists?
  end
  private_class_method :teacher_allocated_in_classroom?

  def self.student_ids_from_enrollments(classroom, discipline)
    StudentEnrollmentsList.new(
      classroom: classroom,
      discipline: discipline,
      search_type: :by_year
    ).student_enrollments.map(&:student_id)
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

  def clear_disciplines_unless_regular
    self.discipline_ids = [] unless regular?
  end

  def disciplines_match_teacher_links
    return unless regular?

    if discipline_ids.blank?
      errors.add(:disciplines, :blank)
      return
    end

    return if teacher_id.blank? || classroom_id.blank? || year.blank?

    allowed_ids = TeacherDisciplineClassroom
      .by_teacher_id(teacher_id)
      .by_classroom(classroom_id)
      .by_year(year)
      .pluck(:discipline_id)

    return if (discipline_ids.map(&:to_i) - allowed_ids).empty?

    errors.add(:disciplines, :not_linked)
  end

  def review_on_after_start_on
    return if review_on.blank? || start_on.blank?
    return if review_on >= start_on

    errors.add(:review_on, :must_be_after_start_on)
  end
end
