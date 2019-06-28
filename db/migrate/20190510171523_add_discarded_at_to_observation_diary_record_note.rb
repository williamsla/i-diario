class AddDiscardedAtToObservationDiaryRecordNote < ActiveRecord::Migration
  def up
    add_column :observation_diary_record_notes, :discarded_at, :datetime
    add_index :observation_diary_record_notes, :discarded_at
  end

  def down
    remove_column :observation_diary_record_notes, :discarded_at
  end
end
