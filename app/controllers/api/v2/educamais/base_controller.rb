# frozen_string_literal: true

module Api
  module V2
    module Educamais
      class BaseController < ActionController::Base
        include Pundit

        protect_from_forgery with: :null_session

        before_action :authenticate_educamais_jwt!
        around_action :handle_customer
        around_action :set_user_current

        rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
        rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

        private

        attr_reader :jwt_claims

        def authenticate_educamais_jwt!
          secret = EducaMais::Config.jwt_secret
          if secret.blank?
            return render json: { error: 'Educa+ não configurado' }, status: :service_unavailable
          end

          token = bearer_token
          @jwt_claims = EducaMais::JwtToken.decode(token, secret: secret)
          return if @jwt_claims.present?

          render json: { error: 'Token inválido ou expirado' }, status: :unauthorized
        end

        def bearer_token
          auth = request.headers['Authorization'].to_s
          if auth.start_with?('Bearer ')
            return auth.sub(/\ABearer /, '').strip
          end

          request.headers['token'].presence
        end

        def current_user
          @current_user ||= User.find_by(id: jwt_claims[:sub])
          return @current_user if @current_user.present?

          raise ActiveRecord::RecordNotFound, 'Usuário não encontrado'
        end

        def current_unity
          @current_unity ||= resolve_current_unity
        end

        def resolve_current_unity
          # Escola do perfil no diário tem prioridade sobre o ID gravado no JWT (pode estar desatualizado)
          unity = current_user.current_unity
          return unity if unity.present?

          Unity.find_by(id: jwt_claims[:unity_id])
        end

        def current_school_year
          jwt_claims[:school_year] || current_user.current_school_year || Date.current.year
        end

        def set_user_current
          User.current = current_user
          yield
        ensure
          User.current = nil
        end

        def handle_customer
          entity = Entity.find(jwt_claims[:entity_id])
          entity.using_connection { yield }
        end

        def render_forbidden
          render json: { error: 'Não autorizado' }, status: :forbidden
        end

        def render_not_found
          render json: { error: 'Não encontrado' }, status: :not_found
        end

        # Array JSON sem raiz — evita { grades: [...] } do ActiveModel::Serializers.
        def render_educamais_json(payload)
          render plain: payload.to_json, content_type: 'application/json'
        end

        def scoped_unities
          profile = CurrentProfile.new(current_user)
          profile.unities
        end

        def ensure_unity_access!(unity_id)
          return if scoped_unities.where(id: unity_id).exists?

          raise Pundit::NotAuthorizedError
        end
      end
    end
  end
end
