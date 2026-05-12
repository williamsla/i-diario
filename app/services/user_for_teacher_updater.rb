require 'i18n'
I18n.enforce_available_locales = false

class UserForTeacherUpdater

  def self.update!(teacher_id, cpf, school_id, function_name)
    new.update!(teacher_id, cpf, school_id, function_name)
  end

  def update!(teacher_id, cpf, school_id, function_name)
    teacher = Teacher.find(teacher_id)
    unity = Unity.find_by(api_code: school_id.to_s)
    
    return if teacher.blank?

    update_user(teacher, cpf, unity, function_name)
  end

  private

  def update_user(teacher, cpf, unity, function_name)
    function_name = function_name.to_s.strip

    role_id = Role.where("name ILIKE ?", "%#{function_name}%").first&.id if function_name.present?

    if function_name.present? && role_id.blank?
      Rails.logger.warn(
        "[UserForTeacherUpdater] Nenhum role encontrado para função '#{function_name}' (teacher_id=#{teacher.id})"
      )
    end

    user = User.find_by(teacher_id: teacher.id, kind: RoleKind::EMPLOYEE)
    return unless user
    
    split_name = teacher.name.strip.split
    first_name = split_name.first
    surname = split_name.drop(1).join(' ')
    
    user.first_name = first_name
    user.last_name = surname
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

    if role_id.present? && unity.present?
      existing_role_without_unity = user.user_roles.find_by(role_id: role_id, unity_id: nil)

      if existing_role_without_unity
        existing_role_without_unity.update!(unity_id: unity.id)
      else
        user.user_roles.find_or_create_by!(role_id: role_id, unity_id: unity.id)
      end
    elsif role_id.present? && unity.blank?
      Rails.logger.warn(
        "[UserForTeacherUpdater] Unity não encontrada ao vincular role (teacher_id=#{teacher.id}, role_id=#{role_id})"
      )
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
