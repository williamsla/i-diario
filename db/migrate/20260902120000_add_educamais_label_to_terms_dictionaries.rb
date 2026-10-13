# frozen_string_literal: true

class AddEducamaisLabelToTermsDictionaries < ActiveRecord::Migration[5.0]
  def change
    add_column :terms_dictionaries, :educamais_label, :string
  end
end
