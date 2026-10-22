# frozen_string_literal: true

class AddDisregardForProgressionToDisciplines < ActiveRecord::Migration[5.0]
  def change
    add_column :disciplines, :disregard_for_progression, :boolean, null: false, default: false
  end
end
