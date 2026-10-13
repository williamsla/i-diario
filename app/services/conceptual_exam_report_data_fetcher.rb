# frozen_string_literal: true

class ConceptualExamReportDataFetcher
  attr_reader :students, :disciplines, :conceptual_exams_by_student

  def initialize(classroom:, step:, teacher_id:)
    @classroom = classroom
    @step = step
    @teacher_id = teacher_id
  end

  def call
    @students = fetch_students
    @disciplines = fetch_disciplines
    @conceptual_exams_by_student = fetch_conceptual_exams
    self
  end

  def reportable?
    students.present? && disciplines.present?
  end

  private

  attr_reader :classroom, :step, :teacher_id

  def fetch_students
    enrolled_ids = ConceptualExamStudentEnrollments.new(
      classroom: classroom,
      discipline: nil,
      start_at: step.start_at,
      end_at: step.end_at
    ).student_enrollments.map(&:student_id)

    # Série conceitual (ou numérica e conceitual) precisa entrar mesmo quando o
    # filtro antigo de score_type só reconhecia a regra exatamente "conceito".
    active_ids = StudentEnrollmentClassroom
      .by_classroom(classroom.id)
      .by_date_range(step.start_at, step.end_at)
      .active
      .joins(student_enrollment: :student)
      .merge(StudentEnrollment.status_attending)
      .pluck('students.id')
      .uniq

    student_ids = (enrolled_ids | (conceptual_exam_student_ids & active_ids)).uniq
    Student.where(id: student_ids).ordered
  end

  def conceptual_exam_student_ids
    scope = ConceptualExam.by_classroom(classroom.id)
    scope = scope.by_step_number(step.step_number) unless GeneralConfiguration.annual_conceptual_evaluation?
    scope.pluck(:student_id)
  end

  def fetch_disciplines
    school_calendar = SchoolCalendar.find_by(unity_id: classroom.unity_id, year: classroom.year)
    return [] if school_calendar.blank?

    teacher_discipline_ids = teacher_discipline_ids_for(school_calendar)

    step_number = step.respond_to?(:to_number) ? step.to_number : step.step_number
    exempted_discipline_ids = ExemptedDisciplinesInStep.discipline_ids(classroom.id, step_number)

    discipline_ids_global = if teacher_discipline_ids.present?
      concept_from_component = TeacherDisciplineClassroom
        .by_classroom(classroom.id)
        .by_teacher_id(teacher_id)
        .by_year(school_calendar.year)
        .by_score_type(ScoreTypes::CONCEPT)
        .pluck(:discipline_id)
      concept_from_exam_rule = Discipline.by_score_type(ScoreTypes::CONCEPT)
        .where(id: teacher_discipline_ids)
        .pluck('disciplines.id')
      concept_discipline_ids = (concept_from_component | concept_from_exam_rule).uniq

      discipline_scope = Discipline.not_grouper.where(id: concept_discipline_ids)
      discipline_scope = discipline_scope.descriptor unless conceptual_exam_batch_layout?

      discipline_scope
        .where.not(id: exempted_discipline_ids)
        .pluck(:id)
    else
      grade_ids = ClassroomsGrade.by_classroom_id(classroom.id).pluck(:grade_id).uniq
      grade_discipline_ids = SchoolCalendarDisciplineGrade
        .where(school_calendar_id: school_calendar.id, grade_id: grade_ids)
        .pluck(:discipline_id)
        .uniq

      discipline_scope = Discipline.by_score_type(ScoreTypes::CONCEPT).not_grouper
      discipline_scope = discipline_scope.descriptor unless conceptual_exam_batch_layout?

      discipline_scope
        .where(id: grade_discipline_ids)
        .where.not(id: exempted_discipline_ids)
        .pluck(:id)
    end

    student_ids = students.map(&:id)
    grade_ids_by_student = ClassroomsGrade
      .by_classroom_id(classroom.id)
      .by_student_id(student_ids)
      .joins(:student_enrollments)
      .pluck('student_enrollments.student_id', :grade_id)
      .each_with_object({}) do |(student_id, grade_id), hash|
        hash[student_id] ||= grade_id
      end

    grade_ids = grade_ids_by_student.values.uniq
    disciplines_by_grade = TeacherDisciplineClassroom
      .by_classroom(classroom.id)
      .by_teacher_id(teacher_id)
      .by_year(school_calendar.year)
      .where(grade_id: grade_ids, discipline_id: discipline_ids_global)
      .pluck(:grade_id, :discipline_id)
      .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(grade_id, discipline_id), hash|
        hash[grade_id] << discipline_id
      end

    result_ids = []
    grade_ids_by_student.each_value do |grade_id|
      grade_discipline_ids = disciplines_by_grade[grade_id] || []
      result_ids = (result_ids + (discipline_ids_global & grade_discipline_ids)).uniq
    end

    # O cruzamento por série apagava o componente quando o vínculo do professor
    # não batia com a série do aluno.
    result_ids = discipline_ids_global if result_ids.blank?
    result_ids = (result_ids | printable_valued_discipline_ids(teacher_discipline_ids)).uniq

    Discipline
      .where(id: result_ids)
      .includes(:knowledge_area)
      .to_a
      .sort_by { |d| [d.knowledge_area&.sequence.to_i, d.knowledge_area&.description.to_s, d.sequence.to_i, d.description] }
  end

  def fetch_conceptual_exams
    scope = ConceptualExam
      .by_classroom(classroom.id)
      .where(student_id: students.map(&:id))
      .includes(:conceptual_exam_values)

    unless GeneralConfiguration.annual_conceptual_evaluation?
      scope = scope.by_step_number(step.step_number)
    end

    # No modo anual, index_by mantém o mais recente por aluno.
    scope.order(:student_id, updated_at: :asc).index_by(&:student_id)
  end

  def conceptual_exam_batch_layout?
    GeneralConfiguration.conceptual_exam_batch_layout?
  end

  def teacher_discipline_ids_for(school_calendar)
    scoped = TeacherDisciplineClassroom.by_classroom(classroom.id).by_teacher_id(teacher_id)
    ids = scoped.by_year(school_calendar.year).pluck(:discipline_id).uniq
    return ids if ids.present?

    scoped.pluck(:discipline_id).uniq
  end

  def printable_valued_discipline_ids(teacher_discipline_ids)
    return [] if teacher_discipline_ids.blank? || students.blank?

    scope = ConceptualExam.by_classroom(classroom.id).where(student_id: students.map(&:id))
    scope = scope.by_step_number(step.step_number) unless GeneralConfiguration.annual_conceptual_evaluation?

    valued_ids = ConceptualExamValue.where(conceptual_exam_id: scope.select(:id))
                                    .distinct
                                    .pluck(:discipline_id)
    valued_ids &= teacher_discipline_ids
    return [] if valued_ids.blank?

    without_groupers = Discipline.not_grouper.where(id: valued_ids).pluck(:id)
    without_groupers.presence || valued_ids
  end
end
