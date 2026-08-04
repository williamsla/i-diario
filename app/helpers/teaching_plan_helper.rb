module TeachingPlanHelper
  def teaching_plan_edit?(teaching_plan)
    can_manage_teaching_plan?(teaching_plan)
  end

  def teaching_plan_destroy?(teaching_plan)
    can_manage_teaching_plan?(teaching_plan)
  end

  def teaching_plan_from_administrator?(teaching_plan)
    teaching_plan&.semed?
  end

  private

  def can_manage_teaching_plan?(teaching_plan)
    current_user.current_role_is_admin_or_employee? ||
      teaching_plan&.teacher&.id == current_teacher.try(:id)
  end
end
