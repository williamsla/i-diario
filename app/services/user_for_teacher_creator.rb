require 'i18n'
I18n.enforce_available_locales = false

class UserForTeacherCreator
  def self.create!(teacher_id, cpf)
    new.create!(teacher_id, cpf)
  end

  def create!(teacher_id, cpf)
    teacher = Teacher.find(teacher_id)

    return if teacher.blank?

    create_user(teacher, cpf)
  end

  private

  def create_user(teacher, cpf)
    role_id = Role.find_by(access_level: AccessLevel::TEACHER)&.id

    raise 'Permissão de professor não encontrada.' if role_id.blank?

    email = "professor#{teacher.api_code}@educaonline.tec.br"

    return if User.find_by(teacher_id: teacher.id, kind: RoleKind::EMPLOYEE)
    return if User.find_by(email: email, kind: RoleKind::EMPLOYEE)

    password = generate_password(teacher.name, cpf)
    login = User.find_by(login: teacher.api_code) ? '' : teacher.api_code

    user = User.find_or_initialize_by(
      login: login,
      email: email,
      kind: RoleKind::EMPLOYEE,
      teacher_id: teacher.id
    )

    return unless user.new_record?

    user.assumed_teacher_id = teacher.id
    user.cpf = cpf
    user.first_name = teacher.name
    user.password = password
    user.password_confirmation = password
    user.status = teacher.active == true ? UserStatus::ACTIVE : UserStatus::PENDING
    user.user_roles.build(role_id: role_id)
    user.without_auditing do
      user.save!(validate: false)
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
