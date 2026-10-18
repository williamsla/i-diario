# frozen_string_literal: true

class AddOriginAndDisciplineToAeeIndividualPlans < ActiveRecord::Migration[5.0]
  def up
    add_column :aee_individual_plans, :origin, :string, null: false, default: 'aee'
    add_reference :aee_individual_plans, :discipline, foreign_key: true, index: true

    remove_index :aee_individual_plans, name: 'idx_aee_individual_plans_on_classroom_student_year'

    add_index :aee_individual_plans,
              [:classroom_id, :student_id, :year],
              unique: true,
              where: "origin = 'aee'",
              name: 'idx_aee_pei_aee_classroom_student_year'

    add_index :aee_individual_plans,
              [:classroom_id, :student_id, :year, :discipline_id],
              unique: true,
              where: "origin = 'regular'",
              name: 'idx_aee_pei_regular_classroom_student_year_discipline'
  end

  def down
    remove_index :aee_individual_plans, name: 'idx_aee_pei_regular_classroom_student_year_discipline'
    remove_index :aee_individual_plans, name: 'idx_aee_pei_aee_classroom_student_year'

    add_index :aee_individual_plans,
              [:classroom_id, :student_id, :year],
              unique: true,
              name: 'idx_aee_individual_plans_on_classroom_student_year'

    remove_reference :aee_individual_plans, :discipline, foreign_key: true
    remove_column :aee_individual_plans, :origin
  end
end
