require 'cpf_cnpj'

class UserForStudentCreator
  def self.create!(student_id, cpf = nil)
    new(cpf).sync!(student_id)
  end

  def self.sync!(student_id, cpf = nil)
    new(cpf).sync!(student_id)
  end

  def initialize(cpf)
    @cpf = cpf
  end

  def sync!(student_id)
    student = Student.find_by(id: student_id)
    return if student.blank?

    role_id = Role.where(access_level: AccessLevel::STUDENT).order(:id).limit(1).pluck(:id).first
    raise 'Permissão de aluno não encontrada.' if role_id.blank?

    user = find_user(student)
    user.student_id ||= student.id
    apply_family_access(user, student)
    assign_new_user(user, student) if user.new_record?

    if user.new_record? || user.changed?
      user.without_auditing do
        user.save!(validate: false)
      end
      user.update_column(:last_password_change, Date.current) if user.last_password_change.blank?
    end

    ensure_student_role(user, role_id)
    user
  end

  private

  attr_reader :cpf

  def find_user(student)
    email = student_email(student)

    User.find_by(student_id: student.id, kind: RoleKind::STUDENT) ||
      User.find_by(email: email, kind: RoleKind::STUDENT) ||
      User.new(email: email, kind: RoleKind::STUDENT, student_id: student.id)
  end

  def assign_new_user(user, student)
    split_name = student.name.to_s.strip.split
    user.login = preferred_login(student)
    user.email = student_email(student)
    user.kind = RoleKind::STUDENT
    user.student_id = student.id
    user.first_name = split_name.first
    user.last_name = split_name.last
    user.fullname = student.name
    user.status = UserStatus::ACTIVE
    ensure_password(user, student)
  end

  def ensure_student_role(user, role_id)
    return if user.user_roles.joins(:role).where(roles: { access_level: AccessLevel::STUDENT }).exists?

    user.user_roles.create!(role_id: role_id)
  end

  def apply_family_access(user, student)
    document = formatted_cpf
    password = StudentPortalPassword.for(name: student.name, cpf: document_digits)

    if document.blank?
      Rails.logger.info(
        "Aluno #{student.api_code} sem CPF válido na sincronização. " \
        "O acesso da família fica para quando o i-Educar enviar o CPF."
      )
      ensure_password(user, student) if user.new_record?
      return
    end

    if cpf_taken?(user)
      Rails.logger.warn(
        "CPF do aluno #{student.api_code} já está em outro usuário. " \
        "O boletim da família não foi ligado a esse CPF."
      )
      ensure_password(user, student) if user.new_record?
      return
    end

    user.cpf = document
    adopt_cpf_login(user, student) if user.persisted?
    return if password.blank?
    return if user.persisted? && !user.valid_password?(legacy_password(student))

    user.password = password
    user.password_confirmation = password
  end

  def ensure_password(user, student)
    return if user.password.present? || user.encrypted_password.present?

    user.password = legacy_password(student)
    user.password_confirmation = legacy_password(student)
  end

  def legacy_password(student)
    "estudante#{student.api_code}"
  end

  def student_email(student)
    "#{student.api_code}@#{Rails.application.secrets[:STUDENT_DOMAIN]}"
  end

  def preferred_login(student)
    digits = cpf_login
    return digits if digits.present?
    return student.api_code if student.api_code.present? && !login_taken?(student.api_code)

    ''
  end

  def cpf_login
    return if formatted_cpf.blank?
    return if login_taken?(document_digits)

    document_digits
  end

  def adopt_cpf_login(user, student)
    digits = document_digits
    return if formatted_cpf.blank? || user.login == digits
    return if login_taken?(digits, user)
    return if user.login.present? && user.login != student.api_code.to_s

    user.login = digits
  end

  def login_taken?(login, user = nil)
    return false if login.blank?

    scope = User.where(login: login)
    scope = scope.where.not(id: user.id) if user&.id.present?
    scope.exists?
  end

  def formatted_cpf
    return if document_digits.blank?
    return unless CPF.valid?(document_digits)

    CPF.new(document_digits).formatted
  end

  def document_digits
    @document_digits ||= cpf.to_s.gsub(/\D/, '')
  end

  def cpf_taken?(user)
    scope = User.where(
      "REGEXP_REPLACE(COALESCE(users.cpf, ''), '[^0-9]', '', 'g') = ?",
      document_digits
    )
    scope = scope.where.not(id: user.id) if user.id.present?
    scope.exists?
  end
end
