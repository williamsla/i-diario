# frozen_string_literal: true

module Api
  module V2
    module Educamais
      class RolesController < BaseController
        STAFF_LEVELS = [
          AccessLevel::ADMINISTRATOR,
          AccessLevel::EMPLOYEE,
          AccessLevel::TEACHER
        ].freeze

        def index
          return render_forbidden unless administrator_access?

          render_educamais_json(
            Role.ordered
                .exclude_administrator_portabilis
                .where(access_level: STAFF_LEVELS)
                .map { |role| role_json(role) }
          )
        end

        private

        def role_json(role)
          {
            id: role.id,
            name: role.name,
            access_level: role.access_level,
            access_level_label: role.access_level_humanize
          }
        end
      end
    end
  end
end
