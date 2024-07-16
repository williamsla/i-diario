class PopulatePositionToObjectivesContentRecords < ActiveRecord::Migration[4.2]
  def change
    execute 'UPDATE objectives_content_records SET position = id'
  end
end
