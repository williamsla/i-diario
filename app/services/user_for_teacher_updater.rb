require 'i18n'
I18n.enforce_available_locales = false

class UserForTeacherUpdater

  def self.update!(teacher_id, cpf, school_id)
    new.update!(teacher_id, cpf, school_id)
  end

  def update!(teacher_id, cpf, school_id)
    teacher = Teacher.find(teacher_id)

    return if teacher.blank?

    update_user(teacher, cpf, school_id)
  end

  private

  def update_user(teacher, cpf, school_id)
    role_id = Role.find_by(access_level: AccessLevel::TEACHER)&.id

    raise 'Permissão de professor não encontrada.' if role_id.blank?

    return unless User.find_by(teacher_id: teacher.id, kind: RoleKind::EMPLOYEE)
    
    user = User.find_by(
      teacher_id: teacher.id,
      assumed_teacher_id: teacher.id
    )

    return if user.blank?

    if user.cpf.length < cpf.length
      Rails.logger.info "Atualizando o CPF antigo do usuário #{user.inspect} para o novo CPF #{cpf}"
      user.cpf = cpf

      new_password = generate_password(teacher.name, cpf)
      user.password = new_password
      user.password_confirmation = new_password
    end
    
    new_status = teacher.active == true ? UserStatus::ACTIVE : UserStatus::PENDING
    if user.status != new_status
      user.status = new_status
    end
    
    if user.user_roles.where(role_id: role_id, school_id: nil).exists?
        user.user_roles.where(role_id: role_id, school_id: nil).first&.update(school_id: school_id)
    else
        user.user_roles.build(role_id: role_id, school_id: school_id)
    end
    

    if user.changed?
        user.without_auditing do
            user.save!(validate: false)
        end
    end
    
  end

  def generate_password(full_name, cpf)
    first_name = full_name.strip.split.first
    first_name_without_accent = I18n.transliterate(first_name).capitalize
    cpf_numbers = cpf.gsub(/\D/, '')
    cpf_numbers_first_3 = cpf_numbers[0, 3]
    "#{first_name_without_accent}@#{cpf_numbers_first_3}"
  end

end
