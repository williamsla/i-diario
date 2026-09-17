# frozen_string_literal: true

module EducaMais
  module UserClaims
    module_function

    def role_payload(user)
      role = user.current_user_role&.role
      {
        role_id: role&.id,
        role_name: role&.name,
        access_level: role&.access_level.presence || (user.admin? ? AccessLevel::ADMINISTRATOR : nil)
      }
    end
  end
end
