# frozen_string_literal: true

class AeeIndividualPlanDiscipline < ApplicationRecord
  belongs_to :aee_individual_plan
  belongs_to :discipline

  validates :discipline_id, uniqueness: { scope: :aee_individual_plan_id }
end
