# frozen_string_literal: true

class AeeIndividualPlanPolicy < ApplicationPolicy
  def create?
    super && AeeIndividualPlan.registration_open_for?(user)
  end

  def edit?
    show?
  end

  def update?
    super && record.owned_by?(user)
  end
end
