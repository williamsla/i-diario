# frozen_string_literal: true

class AeeAttendanceRecordsController < ApplicationController
  has_scope :page, default: 1
  has_scope :per, default: 10
  has_scope :by_student_id, in: :filter

  before_action :require_current_classroom
  before_action :require_current_teacher, only: [:new, :create]
  before_action :require_aee_classroom
  before_action :require_allow_to_modify_prev_years, only: [:create, :update, :destroy]
  before_action :set_aee_attendance_record, only: [:show, :edit, :update, :destroy, :history]
  before_action :fetch_students, only: [:index, :new, :create, :edit, :update]

  def index
    @aee_attendance_records = apply_scopes(aee_attendance_records_scope)
    authorize @aee_attendance_records
  end

  def show
    authorize @aee_attendance_record

    pdf = AeeAttendanceRecordPdf.build(current_entity_configuration, @aee_attendance_record)
    send_pdf(t('routes.aee_attendance_record'), pdf.render)
  end

  def new
    @aee_attendance_record = build_aee_attendance_record.localized
    authorize @aee_attendance_record
  end

  def create
    @aee_attendance_record = AeeAttendanceRecord.new(resource_params)
    assign_context(@aee_attendance_record)
    authorize @aee_attendance_record

    if @aee_attendance_record.save
      respond_with @aee_attendance_record, location: edit_aee_attendance_record_path(@aee_attendance_record)
    elsif (existing = existing_attendance_record)
      redirect_to edit_aee_attendance_record_path(existing),
                  alert: I18n.t('aee_attendance_records.errors.already_exists')
    else
      @aee_attendance_record = @aee_attendance_record.localized
      render :new
    end
  end

  def edit
    @aee_attendance_record = @aee_attendance_record.localized
    authorize @aee_attendance_record
  end

  def update
    @aee_attendance_record.assign_attributes(resource_params)
    authorize @aee_attendance_record

    if @aee_attendance_record.save
      respond_with @aee_attendance_record, location: edit_aee_attendance_record_path(@aee_attendance_record)
    else
      @aee_attendance_record = @aee_attendance_record.localized
      render :edit
    end
  end

  def destroy
    authorize @aee_attendance_record
    @aee_attendance_record.destroy
    respond_with @aee_attendance_record, location: aee_attendance_records_path
  end

  def history
    authorize @aee_attendance_record
  end

  def student_data
    authorize AeeAttendanceRecord, :index?

    student = students_for_classroom.find_by(id: params[:student_id])
    return render json: {} if student.blank?

    record = AeeAttendanceRecord.new
    assign_context(record)
    record.student = student
    record.apply_defaults!

    pei = record.linked_pei

    render json: {
      aee_individual_plan_id: record.aee_individual_plan_id,
      duration: record.duration,
      session_objectives: record.session_objectives,
      pei_goals: pei&.goals,
      pei_strategies: pei&.strategies,
      pei_resources: pei&.resources
    }
  end

  private

  def resource_params
    params.require(:aee_attendance_record).permit(
      :student_id,
      :aee_individual_plan_id,
      :record_date,
      :duration,
      :session_focus,
      :session_objectives,
      :activities_developed,
      :student_response,
      :next_steps
    )
  end

  def set_aee_attendance_record
    @aee_attendance_record = AeeAttendanceRecord.find(params[:id])
  end

  def aee_attendance_records_scope
    AeeAttendanceRecord
      .includes(:student, :classroom, :teacher, :unity)
      .by_classroom(current_user_classroom)
      .by_year(current_user_school_year)
      .ordered
  end

  def build_aee_attendance_record
    AeeAttendanceRecord.new.tap do |record|
      assign_context(record)
      record.record_date = Time.zone.today
      assign_student_from_params(record)
    end
  end

  def assign_context(record)
    record.unity = current_unity
    record.classroom = current_user_classroom
    record.teacher = current_teacher if record.teacher.blank?
    record.user = current_user
    record.school_calendar = current_school_calendar
    record.year = current_user_school_year
  end

  def assign_student_from_params(record)
    student = students_for_classroom.find_by(id: params[:student_id])
    return if student.blank?

    record.student = student
    record.apply_defaults!
  end

  def existing_attendance_record
    return if @aee_attendance_record.student_id.blank? || @aee_attendance_record.record_date.blank?

    AeeAttendanceRecord.find_by(
      classroom_id: current_user_classroom.id,
      student_id: @aee_attendance_record.student_id,
      record_date: @aee_attendance_record.record_date
    )
  end

  def fetch_students
    @students = students_for_classroom
  end

  def students_for_classroom
    student_ids = StudentEnrollmentsList.new(
      classroom: current_user_classroom,
      discipline: current_user_discipline,
      search_type: :by_year
    ).student_enrollments.map(&:student_id)

    Student.where(id: student_ids).ordered
  end

  def require_aee_classroom
    return if is_aee

    flash[:alert] = I18n.t('aee_attendance_records.errors.require_aee_classroom')
    redirect_to root_path
  end
end
