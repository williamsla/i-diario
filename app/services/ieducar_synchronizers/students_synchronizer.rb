class StudentsSynchronizer < BaseSynchronizer
  def synchronize!
    update_students(
      HashDecorator.new(
        api.fetch(
          escola: unity_api_code
        )['alunos']
      )
    )
  rescue IeducarApi::Base::ApiError => error
    synchronization.mark_as_error!(error.message)
  end

  private

  def api_class
    IeducarApi::Students
  end

  def update_students(students)
    allow_create_users_for_students = GeneralConfiguration.current.create_users_for_students_when_synchronize

    students.each do |student_record|
      next if student_record.nome_aluno.blank?

      Student.with_discarded.find_or_initialize_by(api_code: student_record.aluno_id).tap do |student|
        student.name = student_record.nome_aluno
        student.social_name = student_record.nome_social
        student.avatar_url = student_record.foto_aluno
        student.birth_date = student_record.data_nascimento
        student.api = true

        student.uses_differentiated_exam_rule = false if student.uses_differentiated_exam_rule.nil?
        student.save! if student.changed?
        sync_student_user(student, student_record) if allow_create_users_for_students

        discarded = student_record.deleted_at.present?

        student.discard_or_undiscard(discarded)

        if student.discarded?
          student_enrollments = StudentEnrollment.where(student_id: student.id)
          student_enrollment_classrooms = StudentEnrollmentClassroom.where(
            student_enrollment_id: student_enrollments.map(&:id)
          )

          student_enrollments.each(&:discard)
          student_enrollment_classrooms.each(&:discard)
        end
      end
    end
  end

  def sync_student_user(student, student_record)
    UserForStudentCreatorWorker.perform_in(
      1.second,
      entity_id,
      student.id,
      student_document(student_record)
    )
  end

  def student_document(student_record)
    [student_record.try(:cpf), student_record.try(:cpf_aluno)].each do |value|
      digits = normalized_document(value)
      return digits if digits.present?
    end

    nil
  end

  def normalized_document(value)
    return if value.blank? || value.is_a?(Array) || value.is_a?(Hash)

    digits = value.to_s.gsub(/\D/, '')
    digits = digits.rjust(11, '0') if value.is_a?(Numeric) && digits.length < 11
    digits.presence
  end
end
