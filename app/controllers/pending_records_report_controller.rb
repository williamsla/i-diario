class PendingRecordsReportController < ApplicationController
  before_action :require_current_unity

  def form
    steps = steps_fetcher.steps
    
    @pending_records_report_form = PendingRecordsReportForm.new(
      unity_id: current_unity.id,
      school_calendar_year: current_school_year,
      classroom_id: params[:classroom_id],
      teacher_id: params[:teacher_id],
      discipline_id: params[:discipline_id],
      start_at: date_to_br(steps.first&.start_at || Date.current.beginning_of_year),
      end_at: date_to_br(steps.last&.end_at || Date.current)
    )

    set_options_by_user
    fetch_collections
  end

  def report
    fetch_collections

    @pending_records_report_form = PendingRecordsReportForm.new(resource_params)

    if @pending_records_report_form.valid?
      calculator = PendingRecordsCalculator.new(
        unity_id: @pending_records_report_form.unity_id,
        classroom_id: @pending_records_report_form.classroom_id,
        teacher_id: @pending_records_report_form.teacher_id,
        discipline_id: @pending_records_report_form.discipline_id,
        start_date: @pending_records_report_form.start_at,
        end_date: @pending_records_report_form.end_at,
        school_year: @pending_records_report_form.school_calendar_year || current_school_year
      )

      @results = calculator.calculate

      respond_to do |format|
        format.html
        format.json { render json: @results }
      end
    else
      @pending_records_report_form.school_calendar_year = current_school_year
      set_options_by_user
      fetch_collections
      clear_invalid_dates
      render :form
    end
  end

  def classroom_teachers
    return render json: { teachers: [] } if params[:classroom_id].blank?

    classroom = Classroom.find(params[:classroom_id])
    school_year = current_school_year || Date.current.year
    teachers = Teacher.joins(:teacher_discipline_classrooms)
                     .where(teacher_discipline_classrooms: { 
                       classroom_id: classroom.id,
                       year: school_year
                     })
                     .distinct
                     .order_by_name

    render json: { 
      teachers: teachers.map { |t| { id: t.id, name: t.name } }
    }
  end

  def classroom_disciplines
    return render json: { disciplines: [] } if params[:classroom_id].blank?

    classroom = Classroom.find(params[:classroom_id])
    school_year = current_school_year || Date.current.year
    disciplines = Discipline.joins(:teacher_discipline_classrooms)
                           .where(teacher_discipline_classrooms: { 
                             classroom_id: classroom.id,
                             year: school_year
                           })
                           .distinct
                           .ordered

    render json: { 
      disciplines: disciplines.map { |d| { id: d.id, description: d.to_s } }
    }
  end

  private

  def steps_fetcher
    @steps_fetcher ||= begin
      classroom = @pending_records_report_form&.classroom_id.present? ? 
        Classroom.find(@pending_records_report_form.classroom_id) : 
        current_user_classroom
      StepsFetcher.new(classroom || Classroom.new)
    end
  end

  def fetch_collections
    @school_year = current_school_year
  end

  def resource_params
    params.require(:pending_records_report_form).permit(
      :unity_id,
      :classroom_id,
      :teacher_id,
      :discipline_id,
      :start_at,
      :end_at,
      :school_calendar_year
    )
  end

  def clear_invalid_dates
    begin
      resource_params[:start_at].to_date
    rescue ArgumentError
      @pending_records_report_form.start_at = ''
    end

    begin
      resource_params[:end_at].to_date
    rescue ArgumentError
      @pending_records_report_form.end_at = ''
    end
  end

  def set_options_by_user
    @admin_or_teacher ||= current_user.current_role_is_admin_or_employee?
    @unities ||= @admin_or_teacher ? Unity.ordered : [current_user_unity]

    return fetch_linked_by_teacher unless @admin_or_teacher

      @classrooms = Classroom.by_unity(@pending_records_report_form.unity_id)
                           .by_year(current_school_year || Date.current.year)
                           .ordered

    if @pending_records_report_form.classroom_id.present?
      @teachers = Teacher.joins(:teacher_discipline_classrooms)
                        .where(teacher_discipline_classrooms: { 
                          classroom_id: @pending_records_report_form.classroom_id,
                          year: current_school_year || Date.current.year
                        })
                        .distinct
                        .order_by_name

      @disciplines = Discipline.joins(:teacher_discipline_classrooms)
                              .where(teacher_discipline_classrooms: { 
                                classroom_id: @pending_records_report_form.classroom_id,
                                year: current_school_year || Date.current.year
                              })
                              .distinct
                              .ordered
    else
      @teachers = []
      @disciplines = []
    end
  end

  def fetch_linked_by_teacher
    return unless current_teacher

    @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(
      current_teacher.id, 
      current_unity, 
      current_school_year
    )
    @classrooms = @fetch_linked_by_teacher[:classrooms]
    
    classroom_id = @pending_records_report_form.classroom_id || current_user_classroom&.id
    @disciplines = @fetch_linked_by_teacher[:disciplines]
                  .by_classroom_id(classroom_id)
                  .not_descriptor if classroom_id.present?
    
    @teachers = [current_teacher] if current_teacher
  end
end

