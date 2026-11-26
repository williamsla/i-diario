# frozen_string_literal: true

class UserAccessReportPolicy < ApplicationPolicy
  def index?
    (user.administrator? || user.employee?) && user.can_show?(:user_access_reports)
  end

  protected

  def feature_name
    :user_access_reports
  end
end
