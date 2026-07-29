class AddBondAndAllocationDatesToTeacherDisciplineClassrooms < ActiveRecord::Migration
  def change
    add_column :teacher_discipline_classrooms, :start_at, :date
    add_column :teacher_discipline_classrooms, :end_at, :date
    add_column :teacher_discipline_classrooms, :allocation_left_at, :date
  end
end
