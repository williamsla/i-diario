# frozen_string_literal: true

class CreateAeeIndividualPlans < ActiveRecord::Migration[5.0]
  def change
    create_table :aee_individual_plans do |t|
      t.references :unity, null: false, index: true, foreign_key: true
      t.references :classroom, null: false, index: true, foreign_key: true
      t.references :student, null: false, index: true, foreign_key: true
      t.references :teacher, null: false, index: true, foreign_key: true
      t.references :user, null: false, index: true, foreign_key: true
      t.references :school_calendar, null: false, index: true, foreign_key: true
      t.references :aee_case_study, index: true, foreign_key: true

      t.integer :year, null: false
      t.date :start_on, null: false
      t.date :review_on
      t.string :age
      t.text :characteristics
      t.text :psychomotor_skills
      t.text :cognitive_skills
      t.text :socioemotional_skills
      t.text :linguistic_skills
      t.text :identified_difficulties
      t.text :goals
      t.text :resources
      t.text :strategies
      t.text :monitoring
      t.text :short_term_goals
      t.text :long_term_goals
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

    add_index :aee_individual_plans,
              [:classroom_id, :student_id, :year],
              unique: true,
              name: 'idx_aee_individual_plans_on_classroom_student_year'
  end
end
