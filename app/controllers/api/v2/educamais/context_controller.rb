# frozen_string_literal: true

module Api
  module V2
    module Educamais
      class ContextController < BaseController
        def show
          unity = current_unity
          return render_unity_required if unity.blank?

          profile = CurrentProfile.new(current_user)

          render json: {
            user: {
              id: current_user.id,
              name: current_user.name,
              is_admin: current_user.admin? || current_user.administrator?,
              can_semed_view: current_user.admin? || current_user.administrator?
            },
            entity: {
              id: Entity.current.id,
              name: Entity.current.name
            },
            unity: unity_json(unity),
            school_year: current_school_year,
            classroom: profile.classroom_as_json,
            unities: profile.unities_as_json
          }
        end

        private

        def unity_json(unity)
          {
            id: unity.id,
            name: unity.name,
            api_code: unity.api_code
          }
        end

        def render_unity_required
          render json: {
            error: 'Selecione uma escola no i-diário (barra de perfil) antes de abrir o Educa+.'
          }, status: 422
        end
      end
    end
  end
end
