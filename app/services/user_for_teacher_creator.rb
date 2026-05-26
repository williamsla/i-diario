require 'i18n'
I18n.enforce_available_locales = false

class UserForTeacherCreator
  def self.create!(teacher_id, cpf, school_id, function_name)
    new.create!(teacher_id, cpf, school_id, function_name)
  end

  def create!(teacher_id, cpf, school_id, function_name)
    teacher = Teacher.find_by(id: teacher_id)
    if teacher.blank?
      Rails.logger.warn("[UserForTeacherCreator] Teacher não encontrado: teacher_id=#{teacher_id} CPF: #{cpf} School ID: #{school_id} Function Name: #{function_name}")
      return
    end

    unity = Unity.find_by(api_code: school_id.to_s)
    if unity.blank?
      Rails.logger.warn("[UserForTeacherCreator] Unity não encontrada para api_code=#{school_id} (teacher_id=#{teacher_id} CPF: #{cpf} Function Name: #{function_name})")
      return
    end

    create_user(teacher, cpf, unity, function_name)
  end

  private

  def create_user(teacher, cpf, unity, function_name)
    function_name = function_name.to_s.strip
    if function_name.blank?
      Rails.logger.warn("[UserForTeacherCreator] function_name ausente ou vazio (servidor_id=#{teacher.id} CPF: #{cpf} Unity: #{unity.api_code} Function Name: #{function_name})")
      return
    end

    role_id = Role.where("name ILIKE ?", "%#{function_name}%").first&.id
    if role_id.blank?
      Rails.logger.warn("[UserForTeacherCreator] Nenhum role encontrado para função '#{function_name}' (servidor_id=#{teacher.id}) CPF: #{cpf} Unity: #{unity.api_code} Function Name: #{function_name}")
      return
    end

    role = Role.find_by(id: role_id)
    if role.access_level == AccessLevel::ADMINISTRATOR
      Rails.logger.warn("[UserForTeacherCreator] Role é administrador (servidor_id=#{teacher.id}) CPF: #{cpf} Unity: #{unity.api_code} Function Name: #{function_name}")
      return
    end

    email = "professor#{teacher.api_code}@educaonline.tec.br"

    # retorna se encontrar o usuário como servidor cadastrado no sistema
    existing_user = User.find_by(teacher_id: teacher.id, kind: RoleKind::EMPLOYEE)
    if existing_user
      Rails.logger.info("[UserForTeacherCreator] User já existe por teacher_id: #{existing_user.id} CPF: #{cpf} Unity: #{unity.api_code} Function Name: #{function_name}")
      return
    end

    existing_user = User.find_by(email: email, kind: RoleKind::EMPLOYEE)
    if existing_user
      Rails.logger.info("[UserForTeacherCreator] User já existe por email: #{existing_user.id} CPF: #{cpf} Unity: #{unity.api_code} Function Name: #{function_name}")
      return
    end

    login = User.find_by(login: teacher.api_code) ? '' : teacher.api_code

    user = User.find_or_initialize_by(
      login: login,
      email: email,
      kind: RoleKind::EMPLOYEE,
      teacher_id: teacher.id
    )

    unless user.new_record?
      Rails.logger.info("[UserForTeacherCreator] User já existe: #{user.id} CPF: #{cpf} Unity: #{unity.api_code} Function Name: #{function_name}")
      return
    end

    split_name = teacher.name.strip.split
    first_name = split_name.first
    last_name = split_name.last

    password = generate_password(first_name, cpf)

    user.assumed_teacher_id = teacher.id
    user.cpf = cpf
    user.first_name = first_name
    user.last_name = last_name
    user.fullname = teacher.name
    user.password = password
    user.password_confirmation = password
    user.status = teacher.active == true ? UserStatus::ACTIVE : UserStatus::PENDING
    user.user_roles.build(role_id: role_id, unity_id: unity.id)
    
    user.without_auditing do
      user.save!(validate: false)
    end
    
  end

  def generate_password(first_name, cpf)
    first_name_without_accent = I18n.transliterate(first_name).capitalize
    cpf_numbers = cpf.gsub(/\D/, '')
    cpf_numbers_first_3 = cpf_numbers[0, 3]
    "#{first_name_without_accent}@#{cpf_numbers_first_3}"
  end

end
