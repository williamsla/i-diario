class AddBlockModificationsAfterLastStepEndedToGeneralConfigurations < ActiveRecord::Migration
  def change
    add_column :general_configurations, :block_modifications_after_last_step_ended, :boolean,
               default: true, null: false
  end
end
