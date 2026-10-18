# frozen_string_literal: true

class AllowMultipleDisciplinesOnAeeIndividualPlans < ActiveRecord::Migration[5.0]
  def up
    create_table :aee_individual_plan_disciplines do |t|
      t.references :aee_individual_plan, null: false, foreign_key: true, index: false
      t.references :discipline, null: false, foreign_key: true
      t.timestamps
    end

    add_index :aee_individual_plan_disciplines,
              [:aee_individual_plan_id, :discipline_id],
              unique: true,
              name: 'idx_aee_pei_disciplines_on_plan_and_discipline'

    if column_exists?(:aee_individual_plans, :discipline_id)
      execute <<-SQL.squish
        INSERT INTO aee_individual_plan_disciplines
          (aee_individual_plan_id, discipline_id, created_at, updated_at)
        SELECT id, discipline_id, NOW(), NOW()
        FROM aee_individual_plans
        WHERE discipline_id IS NOT NULL
      SQL

      remove_reference :aee_individual_plans, :discipline, foreign_key: true, index: true
    end

    if index_exists?(:aee_individual_plans, name: 'idx_aee_pei_regular_classroom_student_year_discipline')
      remove_index :aee_individual_plans, name: 'idx_aee_pei_regular_classroom_student_year_discipline'
    end

    add_index :aee_individual_plans,
              [:classroom_id, :student_id, :year, :teacher_id],
              unique: true,
              where: "origin = 'regular'",
              name: 'idx_aee_pei_regular_classroom_student_year_teacher'
  end

  def down
    remove_index :aee_individual_plans, name: 'idx_aee_pei_regular_classroom_student_year_teacher'

    add_reference :aee_individual_plans, :discipline, foreign_key: true, index: true

    execute <<-SQL.squish
      UPDATE aee_individual_plans
      SET discipline_id = chosen.discipline_id
      FROM (
        SELECT DISTINCT ON (aee_individual_plan_id) aee_individual_plan_id, discipline_id
        FROM aee_individual_plan_disciplines
        ORDER BY aee_individual_plan_id, id
      ) AS chosen
      WHERE aee_individual_plans.id = chosen.aee_individual_plan_id
    SQL

    drop_table :aee_individual_plan_disciplines

    add_index :aee_individual_plans,
              [:classroom_id, :student_id, :year, :discipline_id],
              unique: true,
              where: "origin = 'regular'",
              name: 'idx_aee_pei_regular_classroom_student_year_discipline'
  end
end
