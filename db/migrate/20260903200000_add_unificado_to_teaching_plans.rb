class AddUnificadoToTeachingPlans < ActiveRecord::Migration
  def change
    add_column :teaching_plans, :unificado, :boolean, default: false, null: false
  end
end
