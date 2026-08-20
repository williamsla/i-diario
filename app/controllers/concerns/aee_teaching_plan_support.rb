# frozen_string_literal: true

module AeeTeachingPlanSupport
  extend ActiveSupport::Concern

  def student_data
    return render json: {} unless is_aee

    authorize controller_name.classify.constantize, :new?

    student = Student.find_by(id: params[:student_id])
    return render json: {} if student.blank?

    render json: AeePrefill.paee_from_case_study(
      student: student,
      classroom: current_user_classroom,
      year: current_user_school_year
    )
  end

  private

  def ensure_aee_teaching_plan_detail(teaching_plan)
    return unless is_aee
    return if teaching_plan.blank?

    detail = teaching_plan.ensure_aee_teaching_plan_detail
    detail.specialized_teacher_name = current_teacher&.name if detail.specialized_teacher_name.blank?
    detail.document_date = Time.zone.today if detail.document_date.blank?
    detail
  end

  def teaching_plan_pdf_for(teaching_plan, regular_pdf)
    return regular_pdf unless teaching_plan.aee?

    AeePaeePdf.build(current_entity_configuration, teaching_plan)
  end
end
