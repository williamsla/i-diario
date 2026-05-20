# frozen_string_literal: true

class RecordAuditTrailPolicy < ApplicationPolicy
  def index?
    @user.can_show?(:record_audit_trails)
  end

  def form?
    index?
  end

  def report?
    index?
  end

  def classroom_teachers?
    index?
  end

  def classroom_disciplines?
    index?
  end

  protected

  def feature_name
    :record_audit_trails
  end
end
