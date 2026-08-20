# frozen_string_literal: true

class AeeIndividualPlansController < ApplicationController
  has_scope :page, default: 1
  has_scope :per, default: 10

  before_action :require_current_classroom
  before_action :require_current_teacher, only: [:new, :create]
  before_action :require_aee_classroom
  before_action :require_allow_to_modify_prev_years, only: [:create, :update, :destroy]
  before_action :set_aee_individual_plan, only: [:show, :edit, :update, :destroy, :history]
  before_action :fetch_students, only: [:index, :new, :create, :edit, :update]

  def index
    @aee_individual_plans = apply_scopes(aee_individual_plans_scope)
    authorize @aee_individual_plans
  end

  def show
    authorize @aee_individual_plan

    pdf = AeeIndividualPlanPdf.build(current_entity_configuration, @aee_individual_plan)
    send_pdf(t('routes.aee_individual_plan'), pdf.render)
  end

  def new
    @aee_individual_plan = build_aee_individual_plan.localized
    authorize @aee_individual_plan
  end

  def create
    @aee_individual_plan = AeeIndividualPlan.new(resource_params)
    assign_context(@aee_individual_plan)
    authorize @aee_individual_plan

    if @aee_individual_plan.save
      respond_with @aee_individual_plan, location: edit_aee_individual_plan_path(@aee_individual_plan)
    else
      @aee_individual_plan = @aee_individual_plan.localized
      render :new
    end
  end

  def edit
    @aee_individual_plan = @aee_individual_plan.localized
    authorize @aee_individual_plan
  end

  def update
    @aee_individual_plan.assign_attributes(resource_params)
    authorize @aee_individual_plan

    if @aee_individual_plan.save
      respond_with @aee_individual_plan, location: edit_aee_individual_plan_path(@aee_individual_plan)
    else
      @aee_individual_plan = @aee_individual_plan.localized
      render :edit
    end
  end

  def destroy
    authorize @aee_individual_plan
    @aee_individual_plan.destroy
    respond_with @aee_individual_plan, location: aee_individual_plans_path
  end

  def history
    authorize @aee_individual_plan
  end

  def student_data
    authorize AeeIndividualPlan, :index?

    student = students_for_classroom.find_by(id: params[:student_id])
    return render json: {} if student.blank?

    record = AeeIndividualPlan.new
    assign_context(record)
    record.student = student
    record.apply_defaults!

    render json: {
      age: record.age,
      birth_date_label: record.birth_date_label,
      characteristics: record.characteristics,
      identified_difficulties: record.identified_difficulties,
      goals: record.goals,
      resources: record.resources,
      strategies: record.strategies,
      monitoring: record.monitoring,
      psychomotor_skills: record.psychomotor_skills,
      cognitive_skills: record.cognitive_skills,
      socioemotional_skills: record.socioemotional_skills,
      linguistic_skills: record.linguistic_skills,
      specialized_teacher_name: record.specialized_teacher_name,
      aee_case_study_id: record.aee_case_study_id
    }
  end

  private

  def resource_params
    params.require(:aee_individual_plan).permit(
      :student_id,
      :aee_case_study_id,
      :start_on,
      :review_on,
      :age,
      :characteristics,
      :psychomotor_skills,
      :cognitive_skills,
      :socioemotional_skills,
      :linguistic_skills,
      :identified_difficulties,
      :goals,
      :resources,
      :strategies,
      :monitoring,
      :short_term_goals,
      :long_term_goals,
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

  def set_aee_individual_plan
    @aee_individual_plan = AeeIndividualPlan.find(params[:id])
  end

  def aee_individual_plans_scope
    AeeIndividualPlan
      .includes(:student, :classroom, :teacher, :unity)
      .by_classroom(current_user_classroom)
      .by_year(current_user_school_year)
      .ordered
  end

  def build_aee_individual_plan
    AeeIndividualPlan.new.tap do |record|
      assign_context(record)
      record.start_on = Time.zone.today
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
    record.apply_defaults!
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

    flash[:alert] = I18n.t('aee_individual_plans.errors.require_aee_classroom')
    redirect_to root_path
  end
end
