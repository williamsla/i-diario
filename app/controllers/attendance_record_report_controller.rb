class AttendanceRecordReportController < ApplicationController
  before_action :require_current_classroom
  before_action :require_current_teacher

  def form
    steps = steps_fetcher.steps
    
    @attendance_record_report_form = AttendanceRecordReportForm.new(
      unity_id: current_unity.id,
      school_calendar_year: current_school_year,
      classroom_id: current_user_classroom.id,
      discipline_id: current_user_discipline.id,
      period: current_teacher_period,
      start_at: date_to_br(steps.first.start_at),
      end_at: date_to_br(steps.last.end_at)
    )

    set_options_by_user
    fetch_collections
    
    # Preenche automaticamente com todas as aulas
    @attendance_record_report_form.class_numbers = (1..@number_of_classes).to_a.join(',') if @attendance_record_report_form.class_numbers.blank?
  end

  def report
    @attendance_record_report_form = AttendanceRecordReportForm.new(resource_params)
    @attendance_record_report_form.school_calendar = SchoolCalendar.find_by(
      unity: @attendance_record_report_form.unity_id,
      year: current_user_school_year
    )

    fetch_collections

    @attendance_record_report_form.class_numbers = (1..@number_of_classes).to_a if @attendance_record_report_form.class_numbers.blank?
    
    # Se não houver quadro de horários, força show_only_discipline_days como false
    unless has_lesson_board?
      @attendance_record_report_form.show_only_discipline_days = false
    end

    if @attendance_record_report_form.valid?
      attendance_record_report = AttendanceRecordReport.build(
        current_entity_configuration,
        current_teacher,
        current_user_school_year,
        @attendance_record_report_form.start_at,
        @attendance_record_report_form.end_at,
        @attendance_record_report_form.daily_frequencies,
        @attendance_record_report_form.enrollment_classrooms_list,
        [],
        @attendance_record_report_form.school_calendar,
        @attendance_record_report_form.second_teacher_signature,
        @attendance_record_report_form.students_frequencies_percentage,
        current_user,
        current_user_classroom.description
      )
      send_pdf(t('routes.attendance_record'), attendance_record_report.render)
    else
      @attendance_record_report_form.school_calendar_year = current_school_year

      set_options_by_user
      fetch_collections
      clear_invalid_dates
      render :form
    end
  end

  def period
    return if params[:classroom_id].blank? || params[:discipline_id].blank?

    fetcher = TeacherPeriodFetcher.new(
      current_teacher.id,
      params[:classroom_id],
      params[:discipline_id]
    )

    periods = fetcher.teacher_periods
    requires_period_selection = fetcher.requires_period_selection?

    render json: {
      period: fetcher.teacher_period,
      periods: periods,
      requires_period_selection: requires_period_selection
    }
  end

  def number_of_classes
    return if params[:classroom_id].blank?

    classroom = Classroom.find(params[:classroom_id])

    school_calendar = CurrentSchoolCalendarFetcher.new(current_unity,classroom,current_school_year).fetch

    render json: school_calendar.number_of_classes
  end

  def frequency_type
    classroom_id = params[:classroom_id].presence
    discipline_id = params[:discipline_id].presence

    return render json: FrequencyTypes::GENERAL if classroom_id.blank? || discipline_id.blank?

    classroom = Classroom.find_by(id: classroom_id)
    return render json: FrequencyTypes::GENERAL if classroom.blank?

    render json: frequency_type_for_classroom_and_discipline(
      classroom: classroom,
      discipline_id: discipline_id
    )
  end

  private

  def fetch_collections
    @number_of_classes = current_school_calendar.number_of_classes
    @teacher = current_teacher
    @period_fetcher = TeacherPeriodFetcher.new(
      current_teacher.id,
      @attendance_record_report_form.classroom_id.presence || current_user.current_classroom_id,
      @attendance_record_report_form.discipline_id.presence || current_user.current_discipline_id
    )
    @period = @period_fetcher.teacher_period
    @period_selectable = @period.to_i == Periods::FULL.to_i || @period_fetcher.requires_period_selection?
    @has_lesson_board = has_lesson_board?
  end

  def has_lesson_board?
    return false if @attendance_record_report_form.blank?
    return false if @attendance_record_report_form.classroom_id.blank?

    begin
      classroom_id = @attendance_record_report_form.classroom_id
      school_year = current_user_school_year || current_school_year

      # Verifica se existe qualquer quadro de horários para a turma
      LessonsBoard.by_classroom(classroom_id)
                  .by_year(school_year)
                  .exists?
    rescue => e
      Rails.logger.error "Erro ao verificar quadro de horários: #{e.message}"
      false
    end
  end

  def resource_params
    params.require(:attendance_record_report_form).permit(:unity_id,
                                                          :classroom_id,
                                                          :period,
                                                          :discipline_id,
                                                          :class_numbers,
                                                          :start_at,
                                                          :end_at,
                                                          :school_calendar_year,
                                                          :current_teacher_id,
                                                          :second_teacher_signature,
                                                          :show_only_discipline_days)
  end

  def clear_invalid_dates
    begin
      resource_params[:start_at].to_date
    rescue ArgumentError
      @attendance_record_report_form.start_at = ''
    end

    begin
      resource_params[:end_at].to_date
    rescue ArgumentError
      @attendance_record_report_form.end_at = ''
    end
  end

  def current_teacher_period
    TeacherPeriodFetcher.new(
      current_teacher.id,
      current_user.current_classroom_id,
      current_user.current_discipline_id
    ).teacher_period
  end

  def set_options_by_user
    @admin_or_teacher ||= current_user.current_role_is_admin_or_employee?
    @unities ||= @admin_or_teacher ? Unity.ordered : [current_user_unity]

    return fetch_linked_by_teacher unless @admin_or_teacher

    @classrooms = Classroom.by_unity(@attendance_record_report_form.unity_id)
                           .by_year(current_user_school_year || Date.current.year)
                           .ordered
    @disciplines = Discipline.by_classroom_id(@attendance_record_report_form.classroom_id)
                             .not_descriptor
  end

  def fetch_linked_by_teacher
    @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(current_teacher.id, current_unity, current_school_year)
    @classrooms = @fetch_linked_by_teacher[:classrooms]
    classroom_id = @attendance_record_report_form.classroom_id
    @disciplines = @fetch_linked_by_teacher[:disciplines].by_classroom_id(classroom_id)
                                                         .not_descriptor
  end

  def frequency_type_for_classroom_and_discipline(classroom:, discipline_id:)
    return FrequencyTypes::GENERAL if classroom.blank?

    exam_rule_frequency_type = classroom.classrooms_grades
                                      .first
                                      &.exam_rule
                                      &.frequency_type
    return FrequencyTypes::BY_DISCIPLINE if exam_rule_frequency_type == FrequencyTypes::BY_DISCIPLINE
    return FrequencyTypes::GENERAL if discipline_id.blank?

    grade_ids = classroom.classrooms_grades.pluck(:grade_id)
    linked_by_discipline = TeacherDisciplineClassroom.where(
      teacher_id: current_teacher.id,
      classroom_id: classroom.id,
      discipline_id: discipline_id,
      year: classroom.year,
      grade_id: grade_ids,
      allow_absence_by_discipline: 1,
      active: true
    ).exists?

    linked_by_discipline ? FrequencyTypes::BY_DISCIPLINE : FrequencyTypes::GENERAL
  end
end
