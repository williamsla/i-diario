require 'i18n'
I18n.enforce_available_locales = false

class UserForTeacherCreator
  def self.create!(teacher_id, cpf, school_id, function_name)
    new.create!(teacher_id, cpf, school_id, function_name)
  end

  def create!(teacher_id, cpf, school_id, function_name)
    teacher = Teacher.find(teacher_id)

    return if teacher.blank?

    unity = Unity.find_by(api_code: school_id)

    create_user(teacher, cpf, unity, function_name)
  end

  private

  def create_user(teacher, cpf, unity, function_name)
    function_name = function_name.downcase
    if function_name.include?('professor')
      role_id = Role.find_by(access_level: AccessLevel::TEACHER)&.id
    elsif function_name.include?('coordenador')
      role_id = Role.find_by(access_level: AccessLevel::EMPLOYEE)&.id
    end

    raise 'Permissão de professor não encontrada.' if role_id.blank?

    email = "professor#{teacher.api_code}@educaonline.tec.br"

    return if User.find_by(teacher_id: teacher.id, kind: RoleKind::EMPLOYEE)
    return if User.find_by(email: email, kind: RoleKind::EMPLOYEE)

    login = User.find_by(login: teacher.api_code) ? '' : teacher.api_code

    user = User.find_or_initialize_by(
      login: login,
      email: email,
      kind: RoleKind::EMPLOYEE,
      teacher_id: teacher.id
    )

    return unless user.new_record?


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
