# frozen_string_literal: true

class CreateTeacherAbsences < ActiveRecord::Migration[5.0]
  def change
    create_table :teacher_absences do |t|
      t.references :unity, null: false, index: true, foreign_key: true
      t.references :classroom, null: false, index: true, foreign_key: true
      t.references :discipline, null: true, index: true, foreign_key: true
      t.references :school_calendar, null: false, index: true, foreign_key: true
      t.references :teacher, null: false, index: true, foreign_key: true
      t.references :user, null: false, index: true, foreign_key: true

      t.date :absence_date, null: false
      t.text :reason, null: false
      t.boolean :will_make_up, null: false, default: false
      t.date :make_up_date, null: true
      t.integer :period, null: true
      t.integer :class_number, null: true

      t.timestamps
    end

    add_index :teacher_absences,
              [:classroom_id, :discipline_id, :absence_date, :teacher_id, :class_number],
              name: 'idx_teacher_absences_on_classroom_discipline_date_teacher_class'

    create_table :teacher_absence_attachments do |t|
      t.references :teacher_absence,
                   null: false,
                   index: { name: 'idx_teacher_absence_attachs_on_teacher_absence_id' },
                   foreign_key: true

      t.timestamps null: false
    end
  end
end
