class DisciplineTeachingPlanPolicy < ApplicationPolicy
  def update?
    return false unless user.can_change?(feature_name)

    can_manage?
  end

  def destroy?
    update?
  end

  private

  def can_manage?
    return true if user.current_role_is_admin_or_employee?
    return false if record.teaching_plan.unificado?

    record.teaching_plan[:teacher_id] == user.current_teacher_id
  end
end
