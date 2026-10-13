# frozen_string_literal: true

class SchoolCalendarPostingDatesPolicy < ApplicationPolicy
  def index?
    update?
  end

  def edit?
    update?
  end

  def update?
    return false unless user.admin? || user.administrator?

    user.can_change?(feature_name)
  end

  protected

  def feature_name
    :school_calendar_posting_dates
  end
end
