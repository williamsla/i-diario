# frozen_string_literal: true

module Api
  module V2
    module Educamais
      class ContextController < BaseController
        def show
          unity = current_unity
          return render_unity_required if unity.blank?

          render json: {
            user: {
              id: current_user.id,
              name: current_user.name,
              is_admin: current_user.admin? || current_user.administrator?,
              can_semed_view: current_user.admin? || current_user.administrator?
            }.merge(EducaMais::UserClaims.role_payload(current_user)),
            entity: {
              id: Entity.current.id,
              name: Entity.current.name,
              ibge_code: EntityConfiguration.current.ibge_code
            },
            unity: unity_json(unity),
            school_year: current_school_year,
            classroom: classroom_json(unity),
            unities: unities_json
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

        def classroom_json(unity)
          classroom = current_user.current_classroom
          return if classroom.blank? || classroom.unity_id.to_i != unity.id

          { id: classroom.id, description: classroom.description }
        end

        # Administrador: todas as escolas. Demais perfis: escolas dos vínculos (user_roles).
        def unities_json
          scoped_unities.map { |item| unity_json(item) }
        rescue StandardError
          current = current_unity
          current ? [unity_json(current)] : []
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
