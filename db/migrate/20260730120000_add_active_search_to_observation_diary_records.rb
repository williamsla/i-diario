class AddActiveSearchToObservationDiaryRecords < ActiveRecord::Migration[5.0]
  def change
    add_column :observation_diary_records, :active_search, :boolean, default: false, null: false
  end
end
