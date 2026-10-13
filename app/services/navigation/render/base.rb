module Navigation
  module Render
    class Base
      def initialize(user, helpers = ::ApplicationController.helpers, routes = ::Rails.application.routes.url_helpers)
        @current_user = user
        @routes = routes
        @helpers = helpers
      end

      def path_method(method)
        return "#" unless method

        routes.send(method)
      end

      protected

      attr_reader :current_user, :routes, :helpers

      delegate :raw, :content_tag, :link_to, :to => :helpers

      def can_show?(feature)
        # rubocop:todo Entender como melhorar esta questão das entidades nos testes
        entity_id = Rails.env.test? ? '1' : Entity.current.id
        role = current_user.current_user_role&.role

        cache_key = [
          'MenuRender#can_show?',
          entity_id,
          current_user.admin?,
          role&.cache_key || current_user.cache_key,
          role&.permissions_cache_key,
          feature
        ]

        Rails.cache.fetch cache_key, expires_in: 1.day do
          policy(feature).index?
        end
      end

      def policy(feature)
        klass = policy_klass_for(feature)

        begin
          result = Pundit::PolicyFinder.new(klass).policy!.new(current_user, klass)
          Rails.logger.info 'LOG: Navigation::Render::Base#policy - Policy found'
          result
        rescue
          result = ApplicationPolicy.new(current_user, klass)
          Rails.logger.info 'LOG: Navigation::Render::Base#policy - Policy fallback'
          result
        end
      end

  def policy_klass_for(feature)
    return Educamais if feature.to_s == 'educamais'
    return Tutorials if feature.to_s == 'tutorials'

        begin
          feature.singularize.camelcase.constantize
        rescue
          feature
        end
      end

      def menu_text(menu_type)
        if menu_type == 'school_term_recovery_diary_records'
          if GeneralConfiguration.semestral_recovery?
            return 'Recuperação Semestral'
          end
        end

        aee_text = aee_menu_text(menu_type)
        return aee_text if aee_text.present?

        Translator.t("navigation.#{menu_type}")
      end

      def aee_menu_text(menu_type)
        return unless aee_navigation_context?

        i18n_key = "aee.navigation.#{menu_type}"
        return I18n.t(i18n_key) if I18n.exists?(i18n_key)

        nil
      end

      def aee_navigation_context?
        return current_user.is_aee if current_user.respond_to?(:is_aee)

        Thread.current[:navigation_is_aee]
      end
    end
  end
end
