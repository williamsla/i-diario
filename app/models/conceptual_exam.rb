class ConceptualExam < ActiveRecord::Base
  include Audit
  include Stepable
  include Discardable
  include ColumnsLockable
  include TeacherRelationable

  not_updatable only: :classroom_id
  teacher_relation_columns only: :classroom

  acts_as_copy_target

  audited
  has_associated_audits

  attr_accessor :unity_id

  before_destroy :valid_for_destruction?

  belongs_to :classroom
  belongs_to :student
  has_many :conceptual_exam_values, lambda {
    includes(:conceptual_exam, discipline: :knowledge_area)
  }, inverse_of: :conceptual_exam, dependent: :destroy

  accepts_nested_attributes_for :conceptual_exam_values, allow_destroy: true

  has_enumeration_for :status, with: ConceptualExamStatus, create_helpers: true

  default_scope -> { kept }

  scope :by_unity, ->(unity) { joins(:classroom).where(classrooms: { unity_id: unity }) }
  scope :by_classroom, ->(classroom) { where(classroom: classroom) }
  scope :by_classroom_id, ->(classroom_id) { where(classroom_id: classroom_id) }
  scope :by_student_id, ->(student_id) { where(student_id: student_id) }
  scope :by_step_number, ->(step_number) { where(step_number: step_number) }
  scope :by_discipline, lambda { |discipline|
    join_conceptual_exam_values.where(conceptual_exam_values: { discipline: discipline })
  }
  scope :by_student_name, lambda { |student_name|
    joins(
      arel_table.join(Student.arel_table).on(
        Student.arel_table[:id].eq(ConceptualExam.arel_table[:student_id])
      ).join_sources
    ).where(
      "(unaccent(students.name) ILIKE unaccent(:student_name) or
        unaccent(students.social_name) ILIKE unaccent(:student_name))",
      student_name: "%#{student_name}%"
    )
  }
  scope :ordered, -> { order(recorded_at: :desc) }
  scope :ordered_by_date_and_student, -> {
    joins(
      arel_table.join(Student.arel_table).on(
        Student.arel_table[:id].eq(ConceptualExam.arel_table[:student_id])
      ).join_sources
    ).order(recorded_at: :desc)
    .order(Student.arel_table[:name])
    .select(Student.arel_table[:name])
  }

  validates :student, :unity_id, presence: true
  validates :recorded_at, posting_date: true, unless: :ignore_date_validates
  validate :student_must_have_conceptual_exam_score_type
  validate :at_least_one_conceptual_exam_value
  validate :uniqueness_of_student
  validate :ensure_student_is_in_classroom

  def self.active
    join_conceptual_exam_values.merge(ConceptualExamValue.active(false))
  end

  def self.by_teacher(teacher_id)
    active.where(
      TeacherDisciplineClassroom.arel_table[:teacher_id].eq(teacher_id)
    ).distinct
  end

  def self.by_status(classroom_id, teacher_id, status)
    classroom = Classroom.find_by(id: classroom_id)
    return none if classroom.blank? || teacher_id.blank?

    incomplete_ids = pending_conceptual_values_for(classroom, teacher_id)
      .distinct
      .pluck(:conceptual_exam_id)

    case status
    when ConceptualExamStatus::INCOMPLETE
      incomplete_ids.empty? ? none : where(id: incomplete_ids)
    when ConceptualExamStatus::COMPLETE
      incomplete_ids.empty? ? all : where.not(id: incomplete_ids)
    else
      none
    end
  end

  # Conceito vazio conta só para a disciplina que este professor lança
  # na série vigente do aluno. Valor em branco de outro professor fica de fora.
  def self.pending_conceptual_values_for(classroom, teacher_id)
    school_calendar = StepsFetcher.new(classroom).school_calendar
    return ConceptualExamValue.none if school_calendar.blank? || teacher_id.blank?

    discipline_ids = launch_discipline_ids_for(classroom, teacher_id)
    return ConceptualExamValue.none if discipline_ids.blank?

    ConceptualExamValue
      .joins(:conceptual_exam)
      .where(value: nil)
      .where('conceptual_exam_values.exempted_discipline IS NOT TRUE')
      .where(conceptual_exams: { classroom_id: classroom.id })
      .where(discipline_id: discipline_ids)
      .where(student_grade_concept_sql(school_calendar.id, teacher_id, classroom.year))
      .where(outside_specific_step_sql)
      .where(student_not_exempted_from_discipline_sql)
  end

  def self.launch_discipline_ids_for(classroom, teacher_id)
    TeacherDisciplineClassroom
      .by_classroom(classroom.id)
      .by_teacher_id(teacher_id)
      .by_year(classroom.year)
      .joins(:discipline)
      .merge(Discipline.descriptor.not_grouper)
      .distinct
      .pluck(:discipline_id)
  end

  def self.student_grade_concept_sql(school_calendar_id, teacher_id, year)
    sanitize_sql_array([<<-SQL.squish, school_calendar_id.to_i, ScoreTypes::CONCEPT, ScoreTypes::NUMERIC_AND_CONCEPT, teacher_id.to_i, year.to_i, ScoreTypes::CONCEPT, ScoreTypes::CONCEPT])
      EXISTS (
        SELECT 1
        FROM classrooms_grades
        INNER JOIN exam_rules
          ON exam_rules.id = classrooms_grades.exam_rule_id
        LEFT JOIN exam_rules differentiated_exam_rules
          ON differentiated_exam_rules.id = exam_rules.differentiated_exam_rule_id
        INNER JOIN student_enrollments
          ON student_enrollments.student_id = conceptual_exams.student_id
         AND student_enrollments.discarded_at IS NULL
        INNER JOIN students
          ON students.id = student_enrollments.student_id
        INNER JOIN school_calendar_discipline_grades
          ON school_calendar_discipline_grades.school_calendar_id = ?
         AND school_calendar_discipline_grades.grade_id = classrooms_grades.grade_id
         AND school_calendar_discipline_grades.discipline_id = conceptual_exam_values.discipline_id
        WHERE classrooms_grades.discarded_at IS NULL
          AND classrooms_grades.id = (
            SELECT classrooms_grades_current.id
            FROM student_enrollment_classrooms
            INNER JOIN student_enrollments enrollments_current
              ON enrollments_current.id = student_enrollment_classrooms.student_enrollment_id
             AND enrollments_current.discarded_at IS NULL
            INNER JOIN classrooms_grades classrooms_grades_current
              ON classrooms_grades_current.id = student_enrollment_classrooms.classrooms_grade_id
             AND classrooms_grades_current.discarded_at IS NULL
            WHERE enrollments_current.student_id = conceptual_exams.student_id
              AND classrooms_grades_current.classroom_id = conceptual_exams.classroom_id
              AND student_enrollment_classrooms.discarded_at IS NULL
              AND COALESCE(student_enrollment_classrooms.joined_at, '') <> ''
              AND CAST(student_enrollment_classrooms.joined_at AS DATE) <= conceptual_exams.recorded_at
            ORDER BY student_enrollment_classrooms.joined_at DESC
            LIMIT 1
          )
          AND (
            exam_rules.score_type = ?
            OR (
              exam_rules.score_type = ?
              AND EXISTS (
                SELECT 1
                FROM teacher_discipline_classrooms
                WHERE teacher_discipline_classrooms.classroom_id = conceptual_exams.classroom_id
                  AND teacher_discipline_classrooms.discipline_id = conceptual_exam_values.discipline_id
                  AND teacher_discipline_classrooms.teacher_id = ?
                  AND teacher_discipline_classrooms.year = ?
                  AND teacher_discipline_classrooms.active = TRUE
                  AND teacher_discipline_classrooms.discarded_at IS NULL
                  AND teacher_discipline_classrooms.score_type = ?
              )
            )
            OR (
              students.uses_differentiated_exam_rule = TRUE
              AND differentiated_exam_rules.score_type = ?
            )
          )
      )
    SQL
  end

  def self.outside_specific_step_sql
    <<-SQL.squish
      NOT EXISTS (
        SELECT 1
        FROM specific_steps
        WHERE specific_steps.classroom_id = conceptual_exams.classroom_id
          AND specific_steps.discipline_id = conceptual_exam_values.discipline_id
          AND specific_steps.discarded_at IS NULL
          AND specific_steps.used_steps != ''
          AND NOT (
            conceptual_exams.step_number = ANY(string_to_array(specific_steps.used_steps, ',')::integer[])
          )
      )
    SQL
  end

  def self.student_not_exempted_from_discipline_sql
    <<-SQL.squish
      NOT EXISTS (
        SELECT 1
        FROM student_enrollment_exempted_disciplines
        INNER JOIN student_enrollments
          ON student_enrollments.id = student_enrollment_exempted_disciplines.student_enrollment_id
         AND student_enrollments.discarded_at IS NULL
        WHERE student_enrollments.student_id = conceptual_exams.student_id
          AND student_enrollment_exempted_disciplines.discipline_id = conceptual_exam_values.discipline_id
          AND student_enrollment_exempted_disciplines.discarded_at IS NULL
          AND conceptual_exams.step_number = ANY(
            string_to_array(COALESCE(student_enrollment_exempted_disciplines.steps, ''), ',')::integer[]
          )
      )
    SQL
  end

  def status(viewer_teacher_id = nil)
    viewer_teacher_id = viewer_teacher_id.presence || teacher_id
    return ConceptualExamStatus::COMPLETE if classroom.blank? || viewer_teacher_id.blank?

    pending = self.class.pending_conceptual_values_for(classroom, viewer_teacher_id)
                  .where(conceptual_exam_id: id)

    pending.exists? ? ConceptualExamStatus::INCOMPLETE : ConceptualExamStatus::COMPLETE
  end

  def valid_for_destruction?
    @valid_for_destruction if defined?(@valid_for_destruction)
    @valid_for_destruction = begin
      self.validation_type = :destroy
      valid?
      !PostingDateChecker.not_allowed_error?(errors[:recorded_at])
    end
  end

  def merge_conceptual_exam_values
    grouped_conceptual_exam_values = conceptual_exam_values.group_by { |e|
      [e.conceptual_exam_id, e.discipline_id]
    }

    self.conceptual_exam_values = grouped_conceptual_exam_values.map do |_key, conceptual_exam_values|
      next conceptual_exam_values.first if conceptual_exam_values.size == 1

      persisted = conceptual_exam_values.find(&:persisted?)
      new_record = conceptual_exam_values.find(&:new_record?)

      persisted.value = new_record.value if new_record.present?

      persisted
    end
  end

  def ignore_date_validates
    !(new_record? || recorded_at != recorded_at_was)
  end

  private

  def student_must_have_conceptual_exam_score_type
    return if student.blank? || classroom.blank? || validation_type.eql?(:destroy)

    permited_score_types = [ScoreTypes::CONCEPT, ScoreTypes::NUMERIC_AND_CONCEPT]
    classroom_grade = ClassroomsGrade.by_student_id(student.id).by_classroom_id(classroom.id)&.first

    return if classroom_grade.blank?

    exam_rule = classroom_grade&.exam_rule
    exam_rule = (exam_rule.differentiated_exam_rule || exam_rule) if student.uses_differentiated_exam_rule

    if student.uses_differentiated_exam_rule
      exam_rule = exam_rule.differentiated_exam_rule || exam_rule
    end

    return if exam_rule.blank? || permited_score_types.include?(exam_rule.score_type)

    errors.add(:student, :classroom_must_have_conceptual_exam_score_type)
  end

  def at_least_one_conceptual_exam_value
    return unless conceptual_exam_values.reject(&:marked_for_destruction?).reject(&:marked_as_invisible?).empty?

    errors.add(:conceptual_exam_values, :at_least_one_conceptual_exam_value)
  end

  def self.join_conceptual_exam_values
    joins(
      arel_table.join(
        ConceptualExamValue.arel_table
      ).on(
        ConceptualExamValue.arel_table[:conceptual_exam_id].
          eq(arel_table[:id])
      ).join_sources
    )
  end

  def uniqueness_of_student
    return if step.blank? || student_id.blank? || validation_type == :destroy

    discipline_ids = conceptual_exam_values.collect(&:discipline_id)
    conceptual_exam = ConceptualExam.joins(:conceptual_exam_values)
                                    .by_step_number(step.step_number)
                                    .where(
                                      student_id: student_id,
                                      classroom_id: classroom_id,
                                      conceptual_exam_values: { discipline_id: discipline_ids }
                                    )

    conceptual_exam = conceptual_exam.where.not(id: id) if persisted?

    errors.add(:student, :taken) if conceptual_exam.exists?
  end

  def ensure_student_is_in_classroom
    return if student_id.blank? || classroom_id.blank? || validation_type == :destroy
    return if student_studied_any_day_in_step?

    errors.add(:base, :student_is_not_in_classroom)
  end

  # A data do lançamento pode ser o último dia da etapa. O conceito vale se a
  # enturmação cruzou qualquer dia do período da etapa selecionada.
  def student_studied_any_day_in_step?
    start_at, end_at = selected_step_period
    return false if start_at.blank? || end_at.blank?

    StudentEnrollment.by_student(student_id)
                     .by_classroom(classroom_id)
                     .by_date_range(start_at, end_at)
                     .exists?
  end

  def selected_step_period
    current_step = step if classroom.present?
    return [current_step.start_at, current_step.end_at] if current_step.present?
    return [recorded_at, recorded_at] if recorded_at.present?
  end
end
