# frozen_string_literal: true

class ConceptualExamReportController < ApplicationController
  before_action :require_current_classroom
  before_action :require_current_teacher

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

      data = ConceptualExamReportDataFetcher.new(
        classroom: classroom,
        step: step,
        teacher_id: current_teacher_id
      ).call

      pdf_report = ConceptualExamReport.build(
        current_entity_configuration,
        current_unity,
        classroom,
        step,
        data.students,
        data.disciplines,
        data.conceptual_exams_by_student
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

  def steps_fetcher(classroom)
    StepsFetcher.new(classroom)
  end
end
