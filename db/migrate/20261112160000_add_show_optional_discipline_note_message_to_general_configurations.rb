# frozen_string_literal: true

class AddShowOptionalDisciplineNoteMessageToGeneralConfigurations < ActiveRecord::Migration[5.0]
  def change
    add_column :general_configurations, :show_optional_discipline_note_message, :boolean,
               null: false, default: true
  end
end
