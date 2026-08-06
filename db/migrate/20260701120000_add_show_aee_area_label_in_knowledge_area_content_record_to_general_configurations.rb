class AddShowAeeAreaLabelInKnowledgeAreaContentRecordToGeneralConfigurations < ActiveRecord::Migration
  def up
    add_column :general_configurations,
               :show_aee_area_label_in_knowledge_area_content_record,
               :boolean,
               default: true
  end

  def down
    remove_column :general_configurations, :show_aee_area_label_in_knowledge_area_content_record
  end
end
