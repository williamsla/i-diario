class AddAnnualConceptualEvaluationToGeneralConfigurations < ActiveRecord::Migration
  def change
    add_column :general_configurations, :annual_conceptual_evaluation, :boolean, default: false, null: false
  end
end
