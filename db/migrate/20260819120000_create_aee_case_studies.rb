# frozen_string_literal: true

class CreateAeeCaseStudies < ActiveRecord::Migration[5.0]
  def change
    create_table :aee_case_studies do |t|
      t.references :unity, null: false, index: true, foreign_key: true
      t.references :classroom, null: false, index: true, foreign_key: true
      t.references :student, null: false, index: true, foreign_key: true
      t.references :teacher, null: false, index: true, foreign_key: true
      t.references :user, null: false, index: true, foreign_key: true
      t.references :school_calendar, null: false, index: true, foreign_key: true

      t.integer :year, null: false
      t.string :grade_stage
      t.string :age
      t.text :identification
      t.string :modality
      t.text :individual_demands
      t.text :barriers_and_context
      t.text :potentialities_and_support
      t.text :accessibility_strategies
      t.text :final_considerations
      t.string :regular_teacher_name
      t.string :specialized_teacher_name
      t.string :mediator_name
      t.string :pedagogical_coordinator_name
      t.string :school_management_name
      t.string :responsible_name
      t.date :document_date, null: false

      t.timestamps
    end

    add_index :aee_case_studies,
              [:classroom_id, :student_id, :year],
              unique: true,
              name: 'idx_aee_case_studies_on_classroom_student_year'
  end
end
