module UnificadoSameStep
  extend ActiveSupport::Concern

  module ClassMethods
    def unificado_on_same_step(teaching_plan)
      return none if teaching_plan.blank?
      return none if teaching_plan.year.blank? || teaching_plan.grade_id.blank?
      return none if teaching_plan.school_term_type_id.blank?

      joins(:teaching_plan).merge(TeachingPlan.unificado).where(
        teaching_plans: {
          year: teaching_plan.year,
          grade_id: teaching_plan.grade_id,
          school_term_type_id: teaching_plan.school_term_type_id,
          school_term_type_step_id: teaching_plan.school_term_type_step_id,
          student_id: teaching_plan.student_id.presence
        }
      )
    end
  end
end
