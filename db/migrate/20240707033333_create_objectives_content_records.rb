class CreateObjectivesContentRecords < ActiveRecord::Migration[4.2]
  def change
    create_table :objectives_content_records do |t|
      t.references :objective, null: false, foreign_key: true
      t.references :content_record, null: false, foreign_key: true

      t.timestamps null: false
    end
  end
end
