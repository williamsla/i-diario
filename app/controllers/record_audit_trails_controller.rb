# frozen_string_literal: true

class RecordAuditTrailsController < ApplicationController
  before_action :require_current_unity

  def form
    authorize RecordAuditTrail

    steps = steps_fetcher.steps

    @record_audit_trail_form = RecordAuditTrailForm.new(
      unity_id: current_unity&.id || params[:unity_id],
      school_calendar_year: current_school_year,
      classroom_id: params[:classroom_id] || current_user_classroom&.id,
      teacher_id: params[:teacher_id] || current_teacher&.id,
      discipline_id: params[:discipline_id] || current_user_discipline&.id,
      start_at: date_to_br(steps.first&.start_at || Date.current.beginning_of_year),
      end_at: date_to_br(steps.last&.end_at || Date.current),
      record_types: RecordAuditTrailForm::RECORD_TYPES
    )

    set_options_by_user
  end

  def report
    authorize RecordAuditTrail

    @record_audit_trail_form = RecordAuditTrailForm.new(resource_params)

    if @record_audit_trail_form.valid?
      @results = RecordAuditTrailSummary.new(
        unity_id: @record_audit_trail_form.unity_id,
        classroom_id: @record_audit_trail_form.classroom_id,
        teacher_id: @record_audit_trail_form.teacher_id,
        discipline_id: @record_audit_trail_form.discipline_id,
        start_date: @record_audit_trail_form.start_at,
        end_date: @record_audit_trail_form.end_at,
        record_types: @record_audit_trail_form.selected_record_types
      ).call

      set_options_by_user
    else
      @record_audit_trail_form.school_calendar_year = current_school_year
      set_options_by_user
      clear_invalid_dates
      render :form
    end
  end

  def classroom_teachers
    authorize RecordAuditTrail

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
      teachers: teachers.map { |teacher| { id: teacher.id, name: teacher.name } }
    }
  end

  def classroom_disciplines
    authorize RecordAuditTrail

    disciplines = disciplines_for_form(params[:classroom_id], params[:teacher_id])

    render json: {
      disciplines: disciplines.map { |discipline| { id: discipline.id, description: discipline.to_s } }
    }
  end

  private

  def disciplines_for_form(classroom_id, teacher_id)
    return Discipline.none if classroom_id.blank? || teacher_id.blank?

    school_year = current_school_year || Date.current.year

    Discipline.joins(:teacher_discipline_classrooms)
              .where(teacher_discipline_classrooms: {
                classroom_id: classroom_id,
                teacher_id: teacher_id,
                year: school_year
              })
              .distinct
              .ordered
  end

  def steps_fetcher
    @steps_fetcher ||= begin
      classroom = if @record_audit_trail_form&.classroom_id.present?
                    Classroom.find(@record_audit_trail_form.classroom_id)
                  else
                    current_user_classroom
                  end
      StepsFetcher.new(classroom || Classroom.new)
    end
  end

  def resource_params
    params.require(:record_audit_trail_form).permit(
      :unity_id,
      :classroom_id,
      :teacher_id,
      :discipline_id,
      :start_at,
      :end_at,
      :school_calendar_year,
      record_types: []
    )
  end

  def clear_invalid_dates
    begin
      resource_params[:start_at].to_date
    rescue ArgumentError
      @record_audit_trail_form.start_at = ''
    end

    begin
      resource_params[:end_at].to_date
    rescue ArgumentError
      @record_audit_trail_form.end_at = ''
    end
  end

  def set_options_by_user
    @admin_or_teacher ||= current_user.current_role_is_admin_or_employee?
    @unities ||= @admin_or_teacher ? Unity.ordered : [current_user_unity]

    return fetch_linked_by_teacher unless @admin_or_teacher

    @classrooms = Classroom.by_unity(@record_audit_trail_form.unity_id)
                           .by_year(current_school_year || Date.current.year)
                           .ordered

    if @record_audit_trail_form.classroom_id.present?
      @teachers = Teacher.joins(:teacher_discipline_classrooms)
                         .where(teacher_discipline_classrooms: {
                           classroom_id: @record_audit_trail_form.classroom_id,
                           year: current_school_year || Date.current.year
                         })
                         .distinct
                         .order_by_name

      @disciplines = disciplines_for_form(
        @record_audit_trail_form.classroom_id,
        @record_audit_trail_form.teacher_id
      )
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

    classroom_id = @record_audit_trail_form.classroom_id || current_user_classroom&.id
    @disciplines = @fetch_linked_by_teacher[:disciplines]
                  .by_classroom_id(classroom_id)
                  .not_descriptor if classroom_id.present?

    @teachers = [current_teacher] if current_teacher
  end
end
