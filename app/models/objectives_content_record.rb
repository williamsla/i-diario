class ObjectivesContentRecord < ApplicationRecord
  audited except: [:content_record_id],
          allow_mass_assignment: true,
          associated_with: [:content_record, :objective]

  belongs_to :content_record
  belongs_to :objective

  before_save :set_position

  private

  def set_position
    self.position = content_record.objectives_created_at_position[objective.id]
  end
end
