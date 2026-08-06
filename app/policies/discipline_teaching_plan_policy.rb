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
    user.current_role_is_admin_or_employee? ||
      record.teaching_plan[:teacher_id] == user.current_teacher_id
  end
end
