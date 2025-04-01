class AddStudentIdToTeachingPlans < ActiveRecord::Migration
  def up
    add_column :teaching_plans, :student_id, :integer, null: true
  end

  def down
    remove_column :teaching_plans, :student_id, :integer, null: true
  end
end
