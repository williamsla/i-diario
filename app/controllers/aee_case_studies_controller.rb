# frozen_string_literal: true

class AeeCaseStudiesController < ApplicationController
  has_scope :page, default: 1
  has_scope :per, default: 10

  before_action :require_current_classroom
  before_action :require_current_teacher, only: [:new, :create]
  before_action :require_aee_classroom
  before_action :require_allow_to_modify_prev_years, only: [:create, :update, :destroy]
  before_action :set_aee_case_study, only: [:show, :edit, :update, :destroy, :history]
  before_action :fetch_students, only: [:index, :new, :create, :edit, :update]

  def index
    @aee_case_studies = apply_scopes(aee_case_studies_scope)
    authorize @aee_case_studies
  end

  def show
    authorize @aee_case_study

    pdf = AeeCaseStudyPdf.build(current_entity_configuration, @aee_case_study)
    send_pdf(t('routes.aee_case_study'), pdf.render)
  end

  def new
    @aee_case_study = build_aee_case_study.localized
    authorize @aee_case_study
  end

  def create
    @aee_case_study = AeeCaseStudy.new(resource_params)
    assign_context(@aee_case_study)
    authorize @aee_case_study

    if @aee_case_study.save
      respond_with @aee_case_study, location: edit_aee_case_study_path(@aee_case_study)
    else
      @aee_case_study = @aee_case_study.localized
      render :new
    end
  end

  def edit
    @aee_case_study = @aee_case_study.localized
    authorize @aee_case_study
  end

  def update
    @aee_case_study.assign_attributes(resource_params)
    authorize @aee_case_study

    if @aee_case_study.save
      respond_with @aee_case_study, location: edit_aee_case_study_path(@aee_case_study)
    else
      @aee_case_study = @aee_case_study.localized
      render :edit
    end
  end

  def destroy
    authorize @aee_case_study
    @aee_case_study.destroy
    respond_with @aee_case_study, location: aee_case_studies_path
  end

  def history
    authorize @aee_case_study
  end

  def student_data
    authorize AeeCaseStudy, :index?

    student = students_for_classroom.find_by(id: params[:student_id])
    return render json: {} if student.blank?

    record = AeeCaseStudy.new(student: student, classroom: current_user_classroom)
    record.apply_student_defaults!

    render json: {
      age: record.age,
      identification: record.identification,
      grade_stage: record.grade_stage,
      modality: record.modality
    }
  end

  private

  def resource_params
    params.require(:aee_case_study).permit(
      :student_id,
      :grade_stage,
      :age,
      :identification,
      :modality,
      :individual_demands,
      :barriers_and_context,
      :potentialities_and_support,
      :accessibility_strategies,
      :final_considerations,
      :regular_teacher_name,
      :specialized_teacher_name,
      :mediator_name,
      :pedagogical_coordinator_name,
      :school_management_name,
      :responsible_name,
      :document_date
    )
  end

  def set_aee_case_study
    @aee_case_study = AeeCaseStudy.find(params[:id])
  end

  def aee_case_studies_scope
    AeeCaseStudy
      .includes(:student, :classroom, :teacher, :unity)
      .by_classroom(current_user_classroom)
      .by_year(current_user_school_year)
      .ordered
  end

  def build_aee_case_study
    AeeCaseStudy.new.tap do |record|
      assign_context(record)
      record.document_date = Time.zone.today
      record.specialized_teacher_name = current_teacher&.name
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
    record.apply_student_defaults!
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

    flash[:alert] = I18n.t('aee_case_studies.errors.require_aee_classroom')
    redirect_to root_path
  end
end
