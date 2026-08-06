class RemoveUniqueIndexFromObservationDiaryRecords < ActiveRecord::Migration[5.0]
  def change
    remove_index :observation_diary_records,
                 name: :idx_obs_diary_on_school_calen_teacher_classroom_discip_and_date
  end
end
