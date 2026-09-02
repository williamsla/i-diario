# frozen_string_literal: true

class PedagogicalTrackingsPolicy < ApplicationPolicy
  def index?
    user.present? && user.can_show?(:pedagogical_trackings)
  end
end
