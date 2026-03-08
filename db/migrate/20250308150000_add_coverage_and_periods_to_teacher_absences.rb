# frozen_string_literal: true

class AddCoverageAndPeriodsToTeacherAbsences < ActiveRecord::Migration[5.0]
  def change
    add_column :teacher_absences, :coverage, :string, default: 'by_classroom', null: false
    add_column :teacher_absences, :periods, :string, array: true, default: []

    change_column_null :teacher_absences, :classroom_id, true
  end
end
