# frozen_string_literal: true

class ConceptualExamReportController < ApplicationController
  before_action :require_current_classroom
  before_action :require_current_teacher
  before_action :require_conceptual_exam_report_enabled, only: [:form, :report, :fetch_step]

  def form
    set_options_by_user
    @classroom = current_user_classroom
    @steps = @classroom.present? ? steps_fetcher(@classroom).steps : []
    @conceptual_exam_report_form = ConceptualExamReportForm.new(
      unity_id: current_unity.id,
      classroom_id: @classroom&.id,
      step_id: @steps.first&.id
    )
  end

  def fetch_step
    return if params[:classroom_id].blank?

    classroom = Classroom.find(params[:classroom_id])
    steps = StepsFetcher.new(classroom)&.steps || []
    steps_json = steps.map { |step| { id: step.id, description: step.to_s, start_at: step.start_at, end_at: step.end_at } }
    render json: steps_json
  end

  def report
    set_options_by_user
    @conceptual_exam_report_form = ConceptualExamReportForm.new(report_params)

    if @conceptual_exam_report_form.valid?
      classroom = Classroom.find(@conceptual_exam_report_form.classroom_id)
      step = StepsFetcher.new(classroom).step_by_id(@conceptual_exam_report_form.step_id)

      students = fetch_report_students(classroom, step)
      disciplines = fetch_report_disciplines(classroom, students, step)
      conceptual_exams_by_student = fetch_conceptual_exams_for_report(classroom, step, students)

      pdf_report = ConceptualExamReport.build(
        current_entity_configuration,
        current_unity,
        classroom,
        step,
        students,
        disciplines,
        conceptual_exams_by_student
      )

      send_pdf(t('conceptual_exam_report.title'), pdf_report.render)
    else
      @classroom = Classroom.find_by(id: @conceptual_exam_report_form.classroom_id)
      @steps = @classroom.present? ? steps_fetcher(@classroom).steps : []
      render :form
    end
  end

  private

  def set_options_by_user
    @unities = [current_user_unity]
    fetch_linked_by_teacher
  end

  def fetch_linked_by_teacher
    @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(
      current_teacher.id,
      current_unity,
      current_school_year,
      current_user_classroom
    )
    @classrooms ||= @fetch_linked_by_teacher[:classrooms]
  end

  def report_params
    params.require(:conceptual_exam_report_form).permit(:unity_id, :classroom_id, :step_id)
  end

  def require_conceptual_exam_report_enabled
    return if conceptual_exam_report_enabled?

    redirect_to conceptual_exams_path, alert: t('conceptual_exam_report.not_available')
  end

  def conceptual_exam_report_enabled?
    conceptual_exam_batch_layout?
  end

  def conceptual_exam_batch_layout?
    Rails.application.secrets.conceptual_exam_batch_layout.present? &&
      Rails.application.secrets.conceptual_exam_batch_layout
  end

  def steps_fetcher(classroom)
    StepsFetcher.new(classroom)
  end

  def fetch_report_students(classroom, step)
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

  def fetch_report_disciplines(classroom, students, step)
    school_calendar = SchoolCalendar.find_by(unity_id: classroom.unity_id, year: classroom.year)
    return Discipline.none if school_calendar.blank?

    year = school_calendar.year
    teacher_discipline_ids = TeacherDisciplineClassroom
      .by_classroom(classroom.id)
      .by_teacher_id(current_teacher_id)
      .by_year(year)
      .pluck(:discipline_id)
      .uniq

    step_number = step.respond_to?(:to_number) ? step.to_number : step.step_number
    exempted_discipline_ids = ExemptedDisciplinesInStep.discipline_ids(classroom.id, step_number)

    # Se o professor não tiver disciplinas (ex.: admin/coordenador), usa as disciplinas conceituais da série no calendário
    discipline_scope = Discipline.by_score_type(ScoreTypes::CONCEPT).not_grouper
    discipline_scope = discipline_scope.descriptor unless conceptual_exam_batch_layout?

    if teacher_discipline_ids.present?
      discipline_ids_global = discipline_scope
        .where(id: teacher_discipline_ids)
        .where.not(id: exempted_discipline_ids)
        .pluck(:id)
    else
      grade_ids = ClassroomsGrade.by_classroom_id(classroom.id).pluck(:grade_id).uniq
      grade_discipline_ids = SchoolCalendarDisciplineGrade
        .where(school_calendar_id: school_calendar.id, grade_id: grade_ids)
        .pluck(:discipline_id)
        .uniq
      discipline_ids_global = discipline_scope
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
    Discipline.where(id: result_ids).includes(:knowledge_area).to_a.sort_by { |d| [d.knowledge_area&.sequence.to_i, d.knowledge_area&.description.to_s, d.sequence.to_i, d.description] }
  end

  def fetch_conceptual_exams_for_report(classroom, step, students)
    conceptual_exams = ConceptualExam
      .by_classroom(classroom.id)
      .by_step_number(step.step_number)
      .where(student_id: students.map(&:id))
      .includes(:conceptual_exam_values)

    conceptual_exams.index_by(&:student_id)
  end
end
