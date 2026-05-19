class AddAverageForPromotionToExamRules < ActiveRecord::Migration[5.2]
  def change
    add_column :exam_rules, :average_for_promotion, :decimal
  end
end
