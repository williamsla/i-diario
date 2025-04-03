class AddStudentIdToLessonPlans < ActiveRecord::Migration
    def up
      add_column :lesson_plans, :student_id, :integer, null: true
    end
  
    def down
      remove_column :lesson_plans, :student_id, :integer, null: true
    end
  end
  