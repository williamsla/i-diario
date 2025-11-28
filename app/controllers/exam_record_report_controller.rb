class ExamRecordReportController < ApplicationController
  before_action :require_current_classroom
  before_action :require_current_teacher

  def form
    @exam_record_report_form = ExamRecordReportForm.new(
      unity_id: current_unity.id,
      classroom_id: current_user_classroom.id,
      discipline_id: current_user_discipline.id
    )

    set_options_by_user
    fetch_collections
    fetch_disciplines_by_classroom
  end

  def report
    @exam_record_report_form = ExamRecordReportForm.new(resource_params)
    set_school_calendars

    if @exam_record_report_form.valid?
      if @exam_record_report_form.report_type == 'all_steps_averages'
        exam_record_report = build_all_steps_averages_report
      else
        exam_record_report = @school_calendar_classroom_steps.any? ? build_by_classroom_steps : build_by_school_steps
      end
      send_pdf(t("routes.exam_record_report"), exam_record_report.render)
    else
      set_options_by_user
      set_school_calendars
      fetch_disciplines_by_classroom

      render :form
    end
  end

  def fetch_step
    return if params[:classroom_id].blank?

    classroom = Classroom.find(params[:classroom_id])
    step_numbers = StepsFetcher.new(classroom)&.steps
    steps = step_numbers.map { |step| { id: step.id, description: step.to_s } }

    render json: steps.to_json
  end

  private

  def resource_params
    params.require(:exam_record_report_form).permit(:unity_id,
                                                    :classroom_id,
                                                    :discipline_id,
                                                    :school_calendar_step_id,
                                                    :school_calendar_classroom_step_id,
                                                    :report_type)
  end

  def build_by_school_steps
    ExamRecordReport.build(
      current_entity_configuration,
      current_teacher,
      current_school_year,
      @exam_record_report_form.step,
      current_test_setting_step(@exam_record_report_form.step),
      @exam_record_report_form.daily_notes,
      @exam_record_report_form.students_enrollments,
      @exam_record_report_form.complementary_exams,
      @exam_record_report_form.school_term_recoveries,
      @exam_record_report_form.recovery_lowest_notes?,
      @exam_record_report_form.lowest_notes
    )
  end

  def build_by_classroom_steps
    ExamRecordReport.build(
      current_entity_configuration,
      current_teacher,
      current_school_calendar.year,
      @exam_record_report_form.classroom_step,
      current_test_setting_step(@exam_record_report_form.classroom_step),
      @exam_record_report_form.daily_notes_classroom_steps,
      @exam_record_report_form.students_enrollments,
      @exam_record_report_form.complementary_exams,
      @exam_record_report_form.school_term_recoveries,
      @exam_record_report_form.recovery_lowest_notes?,
      @exam_record_report_form.lowest_notes
    )
  end

  def fetch_linked_by_teacher
    @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(current_teacher.id, current_unity, current_school_year)
    classroom_id = @exam_record_report_form.classroom_id
    @disciplines ||= @fetch_linked_by_teacher[:disciplines].by_classroom_id(classroom_id)
                                                           .not_descriptor
    @classrooms ||= @fetch_linked_by_teacher[:classrooms]
  end

  def fetch_collections
    @school_calendar_steps = SchoolCalendarStep.where(school_calendar: current_school_calendar).ordered
    @school_calendar_classroom_steps = SchoolCalendarClassroomStep.by_classroom(current_user_classroom.id).ordered
  end

  def set_options_by_user
    @admin_or_teacher ||= current_user.current_role_is_admin_or_employee?
    @unities ||= @admin_or_teacher ? Unity.ordered : [current_user_unity]

    fetch_linked_by_teacher
  end

  def set_school_calendars
    school_calendar = CurrentSchoolCalendarFetcher.new(
      Unity.find(@exam_record_report_form.unity_id),
      Classroom.find(@exam_record_report_form.classroom_id),
      current_school_year
    ).fetch

    @school_calendar_steps = SchoolCalendarStep.where(school_calendar: school_calendar).ordered
    @school_calendar_classroom_steps = SchoolCalendarClassroomStep.by_classroom(@exam_record_report_form.classroom_id).ordered
  end

  def fetch_disciplines_by_classroom
    return if current_user.current_role_is_admin_or_employee?

    classroom_id = @exam_record_report_form.classroom_id
    @disciplines = @disciplines.by_classroom_id(classroom_id).not_descriptor
  end

  def build_all_steps_averages_report
    classroom = Classroom.find(@exam_record_report_form.classroom_id)
    steps_fetcher = StepsFetcher.new(classroom)
    steps = steps_fetcher.steps
    
    students_enrollments = StudentEnrollmentsList.new(
      classroom: @exam_record_report_form.classroom_id,
      discipline: @exam_record_report_form.discipline_id,
      start_at: steps.first&.start_at,
      end_at: steps.last&.end_at,
      score_type: StudentEnrollmentScoreTypeFilters::NUMERIC,
      search_type: :by_date_range,
      show_inactive: false
    ).student_enrollments

    # Ler configuração de recuperação semestral
    # Se não estiver definido, considerar como false
    semestral_recovery = Rails.application.secrets.try(:semestral_recovery) || 
                         Rails.application.secrets.try(:SEMESTRAL_RECOVERY) || 
                         false

    # Decidir qual relatório usar baseado na configuração
    if semestral_recovery
      ExamRecordAllStepsAveragesReport.build(
        current_entity_configuration,
        current_teacher,
        current_school_year,
        classroom,
        Discipline.find(@exam_record_report_form.discipline_id),
        steps,
        students_enrollments
      )
    else
      ExamRecordAllStepsAveragesAdaptiveReport.build(
        current_entity_configuration,
        current_teacher,
        current_school_year,
        classroom,
        Discipline.find(@exam_record_report_form.discipline_id),
        steps,
        students_enrollments
      )
    end
  end
end
