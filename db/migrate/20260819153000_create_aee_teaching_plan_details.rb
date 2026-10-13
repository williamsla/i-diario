# frozen_string_literal: true

class CreateAeeTeachingPlanDetails < ActiveRecord::Migration[5.0]
  def change
    create_table :aee_teaching_plan_details do |t|
      t.references :teaching_plan, null: false, index: { unique: true }, foreign_key: true

      t.string :attendance_period
      t.string :attendance_frequency
      t.string :attendance_duration
      t.string :attendance_composition
      t.text :student_characteristics
      t.text :general_objectives
      t.text :cognitive_objectives
      t.text :psychomotor_objectives
      t.text :socioemotional_objectives
      t.text :activities
      t.text :resources
      t.string :regular_teacher_name
      t.string :specialized_teacher_name
      t.string :mediator_name
      t.string :pedagogical_coordinator_name
      t.string :school_management_name
      t.string :responsible_name
      t.date :document_date

      t.timestamps
    end
  end
end
