# frozen_string_literal: true

class AddCourseToOptionalHolidayMakeups < ActiveRecord::Migration[5.0]
  def change
    add_reference :optional_holiday_unity_makeups, :course, index: true, foreign_key: true

    remove_index :optional_holiday_unity_makeups, name: 'idx_optional_holiday_unity_makeups_uniqueness'

    add_index :optional_holiday_unity_makeups,
              [:optional_holiday_id, :unity_id],
              unique: true,
              where: 'course_id IS NULL',
              name: 'idx_optional_holiday_unity_makeups_general'

    add_index :optional_holiday_unity_makeups,
              [:optional_holiday_id, :unity_id, :course_id],
              unique: true,
              where: 'course_id IS NOT NULL',
              name: 'idx_optional_holiday_unity_makeups_by_course'

    create_table :optional_holiday_course_makeups do |t|
      t.references :optional_holiday, null: false, index: true, foreign_key: true
      t.references :course, null: false, index: true, foreign_key: true
      t.references :user, index: true, foreign_key: true
      t.date :make_up_date, null: false
      t.string :equivalent_weekday

      t.timestamps
    end

    add_index :optional_holiday_course_makeups,
              [:optional_holiday_id, :course_id],
              unique: true,
              name: 'idx_optional_holiday_course_makeups_uniqueness'
  end
end
