# frozen_string_literal: true

class AddEquivalentWeekdayToSchoolCalendarEvents < ActiveRecord::Migration[5.0]
  def change
    add_column :school_calendar_events, :equivalent_weekday, :string
  end
end
