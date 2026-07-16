module AeeHelper
  def aee_label(key, fallback = nil)
    return fallback unless is_aee

    I18n.t("aee.fields.#{key}", default: fallback)
  end

  def aee_navigation_label(menu_type, fallback = nil)
    return fallback unless is_aee

    i18n_key = "aee.navigation.#{menu_type}"
    return I18n.t(i18n_key) if I18n.exists?(i18n_key)

    fallback
  end

  def aee_or_translation(aee_key, translation_value)
    return translation_value unless is_aee

    I18n.t("aee.fields.#{aee_key}", default: translation_value)
  end
end
