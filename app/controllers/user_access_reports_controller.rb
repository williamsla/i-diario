# frozen_string_literal: true

class UserAccessReportsController < ApplicationController
  def index
    authorize UserAccessReport

    @roles = roles_for_current_user
    @report = UserAccessReport.new(
      params[:role_id],
      chart_unity_id: params[:unity_id],
      allowed_role_ids: current_user.administrator? ? nil : @roles.map(&:id),
      school_id: current_user.administrator? ? :all : current_unity&.id
    )
  end

  private

  def roles_for_current_user
    scope = Role.ordered
    return scope if current_user.administrator?

    scope.where(access_level: [AccessLevel::EMPLOYEE, AccessLevel::STUDENT])
  end
end
