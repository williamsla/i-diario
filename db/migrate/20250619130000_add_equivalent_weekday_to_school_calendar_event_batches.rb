# frozen_string_literal: true

class AddEquivalentWeekdayToSchoolCalendarEventBatches < ActiveRecord::Migration[5.0]
  def change
    add_column :school_calendar_event_batches, :equivalent_weekday, :string
  end
end
