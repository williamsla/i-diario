# frozen_string_literal: true

module Api
  module V2
    module Educamais
      class SessionsController < ActionController::Base
        protect_from_forgery with: :null_session

        around_action :handle_customer

        def create
          if EducaMais::Config.jwt_secret.blank? || !EducaMais::Config.enabled?
            return render json: { error: 'Educa+ não configurado' }, status: :service_unavailable
          end

          credential = params[:login].to_s.strip
          password = params[:password].to_s
          if credential.blank? || password.blank?
            return render json: { error: 'Informe usuário e senha.' }, status: :unprocessable_entity
          end

          user = User.find_for_authentication(credentials: credential)
          unless user
            return render json: { error: 'Usuário ou senha inválidos.' }, status: :unauthorized
          end

          if user.access_locked?
            return render json: { error: 'Conta bloqueada. Desbloqueie no i-diário.' }, status: :unauthorized
          end

          unless user.valid_for_authentication? { user.valid_password?(password) }
            if user.access_locked?
              return render json: { error: 'Conta bloqueada. Desbloqueie no i-diário.' }, status: :unauthorized
            end

            return render json: { error: 'Usuário ou senha inválidos.' }, status: :unauthorized
          end

          unless user.active_for_authentication?
            return render json: { error: 'Conta inativa ou ainda não liberada no i-diário.' }, status: :unauthorized
          end

          unless user.can_show?(:educamais)
            return render json: { error: 'Seu usuário não tem acesso ao Educa+. Peça a liberação no i-diário.' }, status: :forbidden
          end

          unity = unity_for(user)
          if unity.blank?
            return render json: {
              error: 'Nenhuma escola vinculada a este usuário. Associe uma escola no i-diário.'
            }, status: :unprocessable_entity
          end

          token = EducaMais::JwtToken.encode(
            EducaMais::LaunchPayload.build(user, request: request, unity: unity),
            secret: EducaMais::Config.jwt_secret
          )
          render json: { token: token }
        rescue StandardError => e
          Rails.logger.error("[educamais] session: #{e.class}: #{e.message}")
          render json: { error: 'Não foi possível entrar. Tente de novo.' }, status: :internal_server_error
        end

        private

        def unity_for(user)
          return user.current_unity if user.current_unity.present?
          return Unity.ordered.first if user.admin? || user.administrator?

          ids = user.user_roles.filter_map(&:unity_id)
          Unity.where(id: ids).ordered.first
        end

        def handle_customer
          entity = Entity.find_by(domain: request.host)
          if entity.blank?
            render json: { error: 'i-diário não encontrado para este endereço.' }, status: :not_found
            return
          end
          if entity.disabled
            render json: { error: 'i-diário indisponível.' }, status: :service_unavailable
            return
          end

          entity.using_connection { yield }
        ensure
          Entity.current = nil
        end
      end
    end
  end
end
