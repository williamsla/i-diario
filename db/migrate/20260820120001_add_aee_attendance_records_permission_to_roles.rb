# frozen_string_literal: true

class AddAeeAttendanceRecordsPermissionToRoles < ActiveRecord::Migration[5.0]
  def up
    Role.where(
      access_level: [
        AccessLevel::ADMINISTRATOR,
        AccessLevel::EMPLOYEE,
        AccessLevel::TEACHER
      ]
    ).find_each do |role|
      permission = role.permissions.find_or_initialize_by(feature: 'aee_attendance_records')
      permission.permission = Permissions::CHANGE
      permission.save_without_auditing
    end
  end

  def down
    RolePermission.where(feature: 'aee_attendance_records').delete_all
  end
end
