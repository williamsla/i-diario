# frozen_string_literal: true

# Quando o SimpleForm exibe a mensagem padrão de campos obrigatórios (pt-BR),
# registra no log o contexto da validação e o rastreamento completo em Ruby (caller_locations),
# para diagnosticar fluxos como /diario-de-frequencia/novo sem exceção explícita.
module SimpleFormErrorNotificationStackTraceLogging
  PT_BR_DEFAULT_MESSAGE =
    'Por favor, verifique os campos obrigatórios e tente novamente.'.freeze
  SIMPLE_FORM_EN_FALLBACK = 'Please review the problems below:'.freeze

  def render
    html = super
    return html unless html.present?
    return html unless default_obrigatorios_notification?(html)

    log_error_notification_context(html)
    html
  end

  private

  def default_obrigatorios_notification?(html)
    stripped = strip_notification_text(html)
    return true if stripped == PT_BR_DEFAULT_MESSAGE
    return true if stripped == SIMPLE_FORM_EN_FALLBACK

    ref = I18n.t(
      'simple_form.error_notification.default_message',
      locale: I18n.locale,
      default: ''
    ).to_s
    return true if ref.present? && stripped == ref.squish

    ref_pt = I18n.t(
      'simple_form.error_notification.default_message',
      locale: :'pt-BR',
      default: ''
    ).to_s
    ref_pt.present? && stripped == ref_pt.squish
  rescue StandardError
    strip_notification_text(html) == PT_BR_DEFAULT_MESSAGE
  end

  def strip_notification_text(html)
    text = if defined?(ActionController::Base) && ActionController::Base.respond_to?(:helpers)
             ActionController::Base.helpers.strip_tags(html.to_s)
           else
             html.to_s.gsub(/<[^>]+>/, ' ')
           end
    text.squish
  end

  def log_error_notification_context(html)
    req = template.try(:request)
    path = req ? req.fullpath : '(sem request)'
    obj = object
    oid =
      if obj.respond_to?(:persisted?) && obj.persisted?
        obj.id
      elsif obj.respond_to?(:new_record?) && obj.new_record?
        'novo'
      else
        obj.try(:id) || obj.object_id
      end

    Rails.logger.error(
      '[SimpleForm] Mensagem padrão de campos obrigatórios — ' \
      "objeto=#{obj.class.name}(id=#{oid}) path=#{path} " \
      "full_messages=#{obj.try(:errors).try(:full_messages).inspect} " \
      "details=#{obj.try(:errors).try(:details).inspect}"
    )
    Rails.logger.error("[SimpleForm] HTML do aviso (truncado 2k): #{html.to_s.truncate(2000)}")

    trace = Kernel.caller_locations(0).map(&:to_s)
    Rails.logger.error("[SimpleForm] Stack trace completo (caller_locations):\n#{trace.join("\n")}")
  rescue StandardError => e
    Rails.logger.error(
      "[SimpleForm] Falha ao registrar stack trace do error_notification: #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}"
    )
  end
end

Rails.application.config.to_prepare do
  next unless defined?(SimpleForm::ErrorNotification)

  unless SimpleForm::ErrorNotification.ancestors.include?(SimpleFormErrorNotificationStackTraceLogging)
    SimpleForm::ErrorNotification.prepend(SimpleFormErrorNotificationStackTraceLogging)
  end
end
