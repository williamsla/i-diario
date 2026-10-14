# frozen_string_literal: true

class DenyAeeAttendanceRecordsPermission < ActiveRecord::Migration[5.0]
  def up
    RolePermission.where(feature: 'aee_attendance_records').find_each do |permission|
      permission.permission = Permissions::DENIED
      permission.save_without_auditing
    end
  end

  def down
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
end
