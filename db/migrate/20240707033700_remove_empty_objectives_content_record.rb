class RemoveEmptyObjectivesContentRecord < ActiveRecord::Migration[4.2]
  class MigrationObjective < ActiveRecord::Base
    self.table_name = :objectives
  end

  class MigrationObjectivesContentRecords < ActiveRecord::Base
    self.table_name = :objectives_content_records
  end

  def change
    MigrationObjective.where("TRIM(COALESCE(description, '')) = ''").each do |objective|
      MigrationObjectivesContentRecords.where(objective_id: objective.id)
                                     .each do |objective_content_record|
        objective_content_record.without_auditing do
          objective_content_record.destroy
        end
      end

      objective.without_auditing do
        objective.destroy
      end
    end
  end
end
