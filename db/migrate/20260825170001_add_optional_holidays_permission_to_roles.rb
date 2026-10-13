# frozen_string_literal: true

class AddOptionalHolidaysPermissionToRoles < ActiveRecord::Migration[5.0]
  def up
    Role.where(
      access_level: [
        AccessLevel::ADMINISTRATOR,
        AccessLevel::EMPLOYEE
      ]
    ).find_each do |role|
      permission = role.permissions.find_or_initialize_by(feature: 'optional_holidays')
      permission.permission = Permissions::CHANGE
      permission.save_without_auditing
    end
  end

  def down
    RolePermission.where(feature: 'optional_holidays').delete_all
  end
end
