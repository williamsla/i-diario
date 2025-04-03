class AddStudentIdToContentRecords < ActiveRecord::Migration
    def up
      add_column :content_records, :student_id, :integer, null: true
    end
  
    def down
      remove_column :content_records, :student_id, :integer, null: true
    end
  end
  