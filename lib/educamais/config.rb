# frozen_string_literal: true

module EducaMais
  module Config
    module_function

    def secrets
      Rails.application.secrets
    end

    def app_url
      secrets[:educamais_url].presence ||
        secrets[:educaindice_url].presence ||
        ENV['EDUCAMAIS_URL'].presence ||
        ENV['EDUCAINDICE_URL'].presence
    end

    def jwt_secret
      secrets[:educamais_jwt_secret].presence ||
        secrets[:educaindice_jwt_secret].presence ||
        ENV['EDUCAMAIS_JWT_SECRET'].presence ||
        ENV['EDUCAINDICE_JWT_SECRET'].presence
    end

    def enabled?
      app_url.present?
    end

    # URL pública da API do i-diário (enviada no JWT ao Educa+).
    # Preferência: secrets/ENV; senão a URL da requisição de launch.
    def idiario_api_url(request: nil)
      explicit = secrets[:idiario_public_url].presence ||
                 ENV['IDIARIO_PUBLIC_URL'].presence
      return explicit.to_s.chomp('/') if explicit.present?

      request&.base_url&.chomp('/')
    end
  end
end
