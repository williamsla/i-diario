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
    last_name = split_name.last
    fullname = teacher.name

    if last_name.equal?('Sobrenome')
      split_name.pop
      last_name = split_name.last
      fullname = split_name.join(' ')
    end
    
    user.first_name = first_name
    user.last_name = last_name
    user.fullname = fullname

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
    
    if user.user_roles.where(role_id: role_id, unity_id: nil).exists?
        user.user_roles.where(role_id: role_id, unity_id: nil).first&.update(unity_id: unity.id)
    elsif !user.user_roles.where(role_id: role_id, unity_id: unity.id).exists?
        user.user_roles.build(role_id: role_id, unity_id: unity.id)
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
