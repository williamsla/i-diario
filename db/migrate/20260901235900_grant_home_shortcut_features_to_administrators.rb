# frozen_string_literal: true

class GrantHomeShortcutFeaturesToAdministrators < ActiveRecord::Migration[5.0]
  FEATURES = %w[pedagogical_trackings educamais].freeze

  def up
    Role.where(
      access_level: [
        AccessLevel::ADMINISTRATOR,
        AccessLevel::EMPLOYEE
      ]
    ).find_each do |role|
      FEATURES.each do |feature|
        permission = role.permissions.find_or_initialize_by(feature: feature)
        permission.permission = Permissions::CHANGE
        permission.save_without_auditing
      end
    end
  end

  def down
    # no-op: não revoga o acesso já concedido
  end
end
