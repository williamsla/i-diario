class RolePermission < ApplicationRecord
  # Permissões Sim/Não/Sem acesso. Só "Sim" (change) libera menu e atalho.
  YES_OR_NO_FEATURES = %w[
    can_change_user_password
    ieducar_api_exam_posting_without_restrictions
    change_school_year
    infrequency_trackings
    educamais
    pedagogical_trackings
    lessons_boards
    copy_discipline_teaching_plan
  ].freeze

  acts_as_copy_target
  audited associated_with: :role, only: [:feature, :permission]

  has_enumeration_for :feature, with: Features
  has_enumeration_for :permission, with: Permissions

  belongs_to :role, touch: true

  def self.can_show?(feature)
    where(arel_table[:feature].eq(feature.to_s)).
      where(arel_table[:permission].in([Permissions::CHANGE, Permissions::READ])).exists?
  end

  def self.can_change?(feature)
    where(arel_table[:feature].eq(feature.to_s)).
      where(arel_table[:permission].eq(Permissions::CHANGE)).exists?
  end

  def access_level_has_feature?(access_level)
    return unless feature

    features = FeaturesAccessLevels.send("#{access_level}_features").map(&:to_sym)
    features.include?(feature.to_sym)
  end
end
