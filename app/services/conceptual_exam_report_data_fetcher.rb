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
    student_ids = StudentEnrollmentClassroom
      .by_classroom(classroom.id)
      .by_date_range(step.start_at, step.end_at)
      .by_score_type(StudentEnrollmentScoreTypeFilters::CONCEPT, classroom.id)
      .active
      .joins(student_enrollment: :student)
      .merge(StudentEnrollment.status_attending)
      .pluck('students.id')
      .uniq

    Student.where(id: student_ids).ordered
  end

  def fetch_disciplines
    school_calendar = SchoolCalendar.find_by(unity_id: classroom.unity_id, year: classroom.year)
    return [] if school_calendar.blank?

    teacher_discipline_ids = TeacherDisciplineClassroom
      .by_classroom(classroom.id)
      .by_teacher_id(teacher_id)
      .by_year(school_calendar.year)
      .pluck(:discipline_id)
      .uniq

    step_number = step.respond_to?(:to_number) ? step.to_number : step.step_number
    exempted_discipline_ids = ExemptedDisciplinesInStep.discipline_ids(classroom.id, step_number)

    discipline_scope = Discipline.by_score_type(ScoreTypes::CONCEPT).not_grouper
    discipline_scope = discipline_scope.descriptor unless conceptual_exam_batch_layout?

    discipline_ids_global = if teacher_discipline_ids.present?
      discipline_scope
        .where(id: teacher_discipline_ids)
        .where.not(id: exempted_discipline_ids)
        .pluck(:id)
    else
      grade_ids = ClassroomsGrade.by_classroom_id(classroom.id).pluck(:grade_id).uniq
      grade_discipline_ids = SchoolCalendarDisciplineGrade
        .where(school_calendar_id: school_calendar.id, grade_id: grade_ids)
        .pluck(:discipline_id)
        .uniq

      discipline_scope
        .where(id: grade_discipline_ids)
        .where.not(id: exempted_discipline_ids)
        .pluck(:id)
    end

    result_ids = []
    students.each do |student|
      cg = ClassroomsGrade.by_student_id(student.id).by_classroom_id(classroom.id).first
      next if cg.blank?

      grade_discipline_ids = SchoolCalendarDisciplineGrade
        .where(school_calendar_id: school_calendar.id, grade_id: cg.grade_id)
        .pluck(:discipline_id)

      result_ids = (result_ids + (discipline_ids_global & grade_discipline_ids)).uniq
    end

    Discipline
      .where(id: result_ids)
      .includes(:knowledge_area)
      .to_a
      .sort_by { |d| [d.knowledge_area&.sequence.to_i, d.knowledge_area&.description.to_s, d.sequence.to_i, d.description] }
  end

  def fetch_conceptual_exams
    ConceptualExam
      .by_classroom(classroom.id)
      .by_step_number(step.step_number)
      .where(student_id: students.map(&:id))
      .includes(:conceptual_exam_values)
      .index_by(&:student_id)
  end

  def conceptual_exam_batch_layout?
    GeneralConfiguration.conceptual_exam_batch_layout?
  end
end
