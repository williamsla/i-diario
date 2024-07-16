class AddPositionToObjectivesContentRecords < ActiveRecord::Migration[4.2]
  def change
    add_column :objectives_content_records, :position, :integer, null: true
  end
end
