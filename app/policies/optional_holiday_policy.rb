# frozen_string_literal: true

class OptionalHolidayPolicy < ApplicationPolicy
  def create?
    administrator? && super
  end

  def destroy?
    create?
  end

  def update?
    return false unless user.can_change?(feature_name)
    return true if administrator?
    employee? && record.makeup_scope_by_school?
  end

  def edit?
    update?
  end

  private

  def administrator?
    user.current_user_role&.role&.access_level == AccessLevel::ADMINISTRATOR
  end

  def employee?
    user.current_user_role&.role&.access_level == AccessLevel::EMPLOYEE
  end
end
