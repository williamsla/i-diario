# frozen_string_literal: true

class CreateAeeAttendanceRecords < ActiveRecord::Migration[5.0]
  def change
    create_table :aee_attendance_records do |t|
      t.references :unity, null: false, index: true, foreign_key: true
      t.references :classroom, null: false, index: true, foreign_key: true
      t.references :student, null: false, index: true, foreign_key: true
      t.references :teacher, null: false, index: true, foreign_key: true
      t.references :user, null: false, index: true, foreign_key: true
      t.references :school_calendar, null: false, index: true, foreign_key: true
      t.references :aee_individual_plan, index: true, foreign_key: true

      t.integer :year, null: false
      t.date :record_date, null: false
      t.string :duration
      t.text :session_focus
      t.text :session_objectives
      t.text :activities_developed
      t.text :student_response
      t.text :next_steps

      t.timestamps
    end

    add_index :aee_attendance_records,
              [:classroom_id, :student_id, :record_date],
              unique: true,
              name: 'idx_aee_attendance_records_on_classroom_student_date'
  end
end
