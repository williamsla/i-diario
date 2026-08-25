# frozen_string_literal: true

class AddSchoolCalendarPostingDatesPermissionToAdministrators < ActiveRecord::Migration[5.0]
  def up
    Role.where(access_level: AccessLevel::ADMINISTRATOR).find_each do |role|
      permission = role.permissions.find_or_initialize_by(feature: 'school_calendar_posting_dates')
      permission.permission = Permissions::CHANGE
      permission.save_without_auditing
    end
  end

  def down
    RolePermission.where(feature: 'school_calendar_posting_dates').delete_all
  end
end
