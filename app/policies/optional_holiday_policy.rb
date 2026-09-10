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
    return false unless employee?
    return false unless record.respond_to?(:school_can_inform_makeup?)

    unity_id = user.current_unity_id.presence || user.current_unity&.id
    return false if unity_id.blank?

    record.school_can_inform_makeup?(unity_id)
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
