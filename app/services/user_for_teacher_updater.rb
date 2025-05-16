require 'i18n'
I18n.enforce_available_locales = false

class UserForTeacherUpdater

  def self.update!(teacher_id, cpf, school_id)
    new.update!(teacher_id, cpf, school_id)
  end

  def update!(teacher_id, cpf, school_id)
    teacher = Teacher.find(teacher_id)

    unity = Unity.find_by(api_code: school_id)
    
    return if teacher.blank?

    update_user(teacher, cpf, unity)
  end

  private

  def update_user(teacher, cpf, unity)
    role_id = Role.find_by(access_level: AccessLevel::TEACHER)&.id

    raise 'Permissão de professor não encontrada.' if role_id.blank?

    return unless User.find_by(teacher_id: teacher.id, kind: RoleKind::EMPLOYEE)

    user = User.by_cpf(cpf).first          

    return if user.nil?

    split_name = teacher.name.strip.split
    first_name = split_name.first
    
    user.first_name = first_name
    user.last_name = split_name.last
    user.fullname = teacher.name

    if user.cpf.to_s.length < cpf.to_s.length || (user.cpf.to_s.length == cpf.to_s.length && user.cpf != cpf)
      user.cpf = cpf

      new_password = generate_password(first_name, cpf)
      user.password = new_password
      user.password_confirmation = new_password
    end
    
    new_status = teacher.active == true ? UserStatus::ACTIVE : UserStatus::PENDING
    if user.status != new_status
      user.status = new_status
    end

    # Verifica se há um vínculo com o role e unity_id nulo
    existing_role_without_unity = user.user_roles.find_by(role_id: role_id, unity_id: nil)

    if existing_role_without_unity
      # Atualiza o vínculo existente para ter o unity_id atual
      existing_role_without_unity.update!(unity_id: unity.id)
    else
      # Verifica se já existe um vínculo com o mesmo role_id e unity_id
      unless user.user_roles.exists?(role_id: role_id, unity_id: unity.id)
        # Cria um novo vínculo com role_id e unity_id informados
        user.user_roles.create!(role_id: role_id, unity_id: unity.id)
      end
    end
    
    if user.changed?
        user.without_auditing do
            user.save!(validate: false)
        end
    end
    
  end

  def generate_password(first_name, cpf)
    first_name_without_accent = I18n.transliterate(first_name).capitalize
    cpf_numbers = cpf.gsub(/\D/, '')
    cpf_numbers_first_3 = cpf_numbers[0, 3]
    "#{first_name_without_accent}@#{cpf_numbers_first_3}"
  end

end
