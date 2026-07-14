module TutorialProfiles
  ROLE_KEYWORDS = {
    assistente_social: [/assistente social/],
    coordenador: [/coordenador/],
    professor_aee: [/aee/],
    professor_educacao_infantil: [/infantil/, /educacao infantil/],
    professor: [/professor/]
  }.freeze


  module_function

  def allowed?(user)
    return false unless user
    return true if admin_user?(user)

    role = user.current_user_role&.role
    return false unless role
    return true if role.teacher?

    role_type(role).present?
  end

  def visible_profiles(user, is_aee: false, is_infantil: false)
    return [] unless user

    if assistente_social?(user)
      return [:assistente_social]
    end

    profiles = [classroom_profile(is_aee: is_aee, is_infantil: is_infantil)]

    if admin_user?(user)
      profiles << :coordenador
      profiles << :assistente_social
    elsif coordenador?(user)
      profiles << :coordenador
    end

    profiles.uniq
  end

  def default_profile(user, is_aee: false, is_infantil: false)
    visible_profiles(user, is_aee: is_aee, is_infantil: is_infantil).first
  end

  def classroom_profile(is_aee: false, is_infantil: false)
    return :professor_aee if is_aee
    return :professor_educacao_infantil if is_infantil

    :professor
  end

  def role_type(role)
    return nil unless role

    name = normalize_role_name(role.name)

    ROLE_KEYWORDS.each do |key, patterns|
      return key if patterns.any? { |pattern| name.match?(pattern) }
    end

    nil
  end

  def assistente_social?(user)
    role_type(user.current_user_role&.role) == :assistente_social
  end

  def coordenador?(user)
    role_type(user.current_user_role&.role) == :coordenador
  end

  def admin_user?(user)
    user.admin? || user.administrator? || user.has_administrator_access_level?
  end

  def normalize_role_name(name)
    I18n.transliterate(name.to_s).downcase
  end
end
