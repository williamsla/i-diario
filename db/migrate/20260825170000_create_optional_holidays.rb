# frozen_string_literal: true

class CreateOptionalHolidays < ActiveRecord::Migration[5.0]
  def change
    create_table :optional_holidays do |t|
      t.integer :year, null: false
      t.date :holiday_date, null: false
      t.string :description, null: false
      t.string :periods, array: true, default: [], null: false
      t.string :makeup_scope, null: false, default: 'municipal'
      t.date :make_up_date
      t.string :equivalent_weekday
      t.references :user, null: false, index: true, foreign_key: true

      t.timestamps
    end

    add_index :optional_holidays, [:year, :holiday_date], unique: true, name: 'idx_optional_holidays_on_year_and_date'

    create_table :optional_holiday_attachments do |t|
      t.references :optional_holiday,
                   null: false,
                   index: { name: 'idx_optional_holiday_attachs_on_optional_holiday_id' },
                   foreign_key: true
      t.string :attachment
      t.string :attachment_file_name_with_hash

      t.timestamps null: false
    end

    create_table :optional_holiday_unity_makeups do |t|
      t.references :optional_holiday, null: false, index: true, foreign_key: true
      t.references :unity, null: false, index: true, foreign_key: true
      t.references :user, index: true, foreign_key: true
      t.date :make_up_date, null: false
      t.string :equivalent_weekday

      t.timestamps
    end

    add_index :optional_holiday_unity_makeups,
              [:optional_holiday_id, :unity_id],
              unique: true,
              name: 'idx_optional_holiday_unity_makeups_uniqueness'

    add_column :school_calendar_events, :optional_holiday_id, :integer
    add_index :school_calendar_events, :optional_holiday_id, name: 'idx_school_calendar_events_on_optional_holiday_id'
    add_foreign_key :school_calendar_events, :optional_holidays, column: :optional_holiday_id
  end
end
