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

    def allowed_entity_names
      names = secrets[:educamais_entity_names].presence ||
              secrets[:educaindice_entity_names].presence ||
              env_entity_names

      Array(names).map { |name| name.to_s.strip }.reject(&:blank?)
    end

    def enabled?
      return false unless app_url.present?
      return true if allowed_entity_names.blank?

      entity = Entity.current
      return false if entity.blank?

      allowed_entity_names.any? { |name| name.casecmp?(entity.name.to_s) }
    end

    def env_entity_names
      value = ENV['EDUCAMAIS_ENTITY_NAMES'].presence || ENV['EDUCAINDICE_ENTITY_NAMES'].presence
      return if value.blank?

      value.split(',').map(&:strip).reject(&:blank?)
    end
    private_class_method :env_entity_names

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
