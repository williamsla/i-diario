# frozen_string_literal: true

class EducamaisPolicy < ApplicationPolicy
  def index?
    launch?
  end

  def launch?
    return false unless EducaMais::Config.enabled?

    user.present? && user.can_show?(:educamais)
  end
end
