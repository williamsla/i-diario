# frozen_string_literal: true

class GrantHomeShortcutFeaturesToAdministrators < ActiveRecord::Migration[5.0]
  FEATURES = %w[pedagogical_trackings educamais].freeze

  def up
    Role.find_each do |role|
      FEATURES.each do |feature|
        permission = role.permissions.find_or_initialize_by(feature: feature)
        next if permission.persisted?

        permission.permission = Permissions::DENIED
        permission.save_without_auditing
      end
    end
  end

  def down
    # no-op: não altera o que o administrador já configurou no perfil
  end
end
