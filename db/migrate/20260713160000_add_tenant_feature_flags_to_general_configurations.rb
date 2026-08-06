class AddTenantFeatureFlagsToGeneralConfigurations < ActiveRecord::Migration
  def change
    add_column :general_configurations, :show_objectives, :boolean, default: true, null: false
    add_column :general_configurations, :semestral_recovery, :boolean, default: false, null: false
    add_column :general_configurations, :conceptual_exam_batch_layout, :boolean, default: false, null: false
  end
end
