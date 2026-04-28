class AddDescriptiveExamsSemesterCalendarStepsToGeneralConfigurations < ActiveRecord::Migration
  def change
    add_column :general_configurations, :descriptive_exams_semester_calendar_steps, :boolean, default: false, null: false
  end
end
