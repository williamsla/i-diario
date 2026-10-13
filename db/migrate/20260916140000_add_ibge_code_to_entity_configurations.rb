# frozen_string_literal: true

class AddIbgeCodeToEntityConfigurations < ActiveRecord::Migration[5.0]
  def change
    add_column :entity_configurations, :ibge_code, :string
  end
end
