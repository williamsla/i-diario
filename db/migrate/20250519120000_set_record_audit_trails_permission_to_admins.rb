# frozen_string_literal: true

class SetRecordAuditTrailsPermissionToAdmins < ActiveRecord::Migration[4.2]
  def up
    [AccessLevel::ADMINISTRATOR, AccessLevel::EMPLOYEE].each do |access_level|
      Role.where(access_level: access_level).find_each do |role|
        permission = role.permissions.find_or_initialize_by(feature: 'record_audit_trails')
        permission.permission = Permissions::CHANGE
        permission.save_without_auditing
      end
    end
  end

  def down
    RolePermission.where(feature: 'record_audit_trails').delete_all
  end
end
