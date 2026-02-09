# frozen_string_literal: true

class ConceptualExamPolicy < ApplicationPolicy
  def new_batch?
    create?
  end

  def form_batch?
    create?
  end

  def create_batch?
    create?
  end
end
