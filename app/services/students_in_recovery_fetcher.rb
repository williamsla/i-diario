# OPTIMIZE: Performance na pagina diario-de-recuperacoes-de-etapas/novo
# A pagina diario-de-recuperacoes-de-etapas/novo demora para carregar por
# conta desse service, toda a filtragem é feita via cadeia de transformação,
# trazendo os dados para a memoria e tratando aqui. Para diminuir o tempo de
# carregamento e o custi de infra, o ideal seria refatorar essa classe e delegar
# mais filtros ao postgres antes de transformar os dados em memoria
class StudentsInRecoveryFetcher
  # Mesma regra de StudentEnrollmentsList#numeric_exam_score_type_permitted?:
  # só série com nota numérica (ou numérica e conceitual) lança recuperação.
  NUMERIC_SCORE_TYPES = [ScoreTypes::NUMERIC, ScoreTypes::NUMERIC_AND_CONCEPT].freeze

  def initialize(ieducar_api_configuration, classroom_id, discipline_id, step_id, date)
    @ieducar_api_configuration = ieducar_api_configuration
    @classroom_id = classroom_id
    @discipline_id = discipline_id
    @step_id = step_id
    @date = date
  end

  def fetch
    @students = []

    if (classroom_grades_with_recovery_rule.first.exam_rule.differentiated_exam_rule.blank? ||
      classroom_grades_with_recovery_rule.first.exam_rule.differentiated_exam_rule.recovery_type == classroom_grades_with_recovery_rule.first.exam_rule.recovery_type)
      @students += fetch_by_recovery_type(classroom_grades_with_recovery_rule.first.exam_rule.recovery_type)
    else
      @students += fetch_by_recovery_type(classroom_grades_with_recovery_rule.first.exam_rule.recovery_type, false)
      @students += fetch_by_recovery_type(classroom_grades_with_recovery_rule.first.exam_rule.differentiated_exam_rule.recovery_type, true)
    end

    @students.uniq!

    @students
  end

  private

  def fetch_by_recovery_type(recovery_type, differentiated = nil)
    case recovery_type
    when RecoveryTypes::PARALLEL
      students = fetch_students_in_parallel_recovery(differentiated)
    when RecoveryTypes::SPECIFIC
      students = fetch_students_in_specific_recovery(differentiated)
    else
      students = []
    end

    students
  end

  def classroom
    @classroom ||= Classroom.find(@classroom_id)
  end

  def classroom_grades_with_recovery_rule
    return @classroom_grade if @classroom_grade.present?

    @classroom_grade = []

    classroom_grades&.each do |classroom_grade|
      next unless grade_has_numeric_score?(classroom_grade)

      @classroom_grade << classroom_grade unless classroom_grade.exam_rule.recovery_type.eql?(0)
    end

    if @classroom_grade.empty?
      classroom_grades.select { |classroom_grade| grade_has_numeric_score?(classroom_grade) }.presence || classroom_grades
    else
      @classroom_grade
    end
  end

  def grade_has_numeric_score?(classroom_grade)
    exam_rule = classroom_grade.exam_rule
    return false if exam_rule.blank?

    numeric_rule?(exam_rule) || numeric_rule?(exam_rule.differentiated_exam_rule)
  end

  def numeric_rule?(exam_rule)
    exam_rule.present? && NUMERIC_SCORE_TYPES.include?(exam_rule.score_type)
  end

  def classroom_grades
    classroom.classrooms_grades.includes(exam_rule: :differentiated_exam_rule)
  end

  def discipline
    @discipline ||= Discipline.find(@discipline_id)
  end

  def steps_fetcher
    @steps_fetcher ||= StepsFetcher.new(classroom)
  end

  def step
    @step ||= steps_fetcher.step_by_id(@step_id)
  end

  def student_enrollments(classroom_grade_ids)
    end_at = @date.to_date > step.end_at ? step.end_at : @date.to_date

    @student_enrollments ||= fetch_student_enrollments(end_at, classroom_grade_ids, discipline, step, classroom)
  end

  def fetch_student_enrollments(end_at, classroom_grade_ids, discipline, step, classroom)
    student_enrollments = StudentEnrollmentsRetriever.call(
      classrooms: classroom,
      disciplines: discipline,
      start_at: step.start_at,
      end_at: end_at,
      classroom_grades: classroom_grade_ids,
      search_type: :by_date_range,
      left_at: true
    )
    StudentEnrollment.includes(
      :student,
      student_enrollment_classrooms: { classrooms_grade: { exam_rule: :differentiated_exam_rule } }
    ).where(id: student_enrollments.map(&:id)).order('students.name ASC')
  end

  def fetch_students_in_parallel_recovery(differentiated = nil)
    students = filter_students_in_recovery

    if classroom_grades_with_recovery_rule.first.exam_rule.parallel_recovery_average
      students = students.select do |student|
        average = student.average(classroom, discipline, step) || 0
        average < classroom_grades_with_recovery_rule.first.exam_rule.parallel_recovery_average
      end
    end

    filter_differentiated_students(students, differentiated)
  end

  def filter_students_in_recovery
    classroom_grade_ids = classroom_grades_with_recovery_rule.map(&:id)
    student_enrollments_in_recovery = student_enrollments(classroom_grade_ids)

    student_enrollments_in_recovery.select { |enrollment| numeric_score_type?(enrollment) }.map(&:student)
  end

  # Série conceitual ou parecer (não usa nota) não recebe lançamento numérico.
  # Regra diferenciada do aluno prevalece sobre a regra da série.
  def numeric_score_type?(enrollment)
    student = enrollment.student
    exam_rule = exam_rule_for(enrollment, student)
    return false if exam_rule.blank?

    NUMERIC_SCORE_TYPES.include?(exam_rule.score_type)
  end

  def exam_rule_for(enrollment, student)
    classroom_grade = classroom_grade_on_date(enrollment)
    return if classroom_grade.blank?

    exam_rule = classroom_grade.exam_rule
    return exam_rule unless student&.uses_differentiated_exam_rule

    exam_rule&.differentiated_exam_rule || exam_rule
  end

  def classroom_grade_on_date(enrollment)
    reference_date = @date.to_date
    enrollment_classrooms = enrollment.student_enrollment_classrooms.select { |enrollment_classroom|
      enrollment_classroom.classrooms_grade&.classroom_id == classroom.id
    }
    current = enrollment_classrooms.find { |enrollment_classroom| enrolled_on?(enrollment_classroom, reference_date) }

    (current || enrollment_classrooms.last)&.classrooms_grade
  end

  def enrolled_on?(enrollment_classroom, date)
    joined_at = enrollment_classroom.joined_at.presence
    left_at = enrollment_classroom.left_at.presence
    return false if joined_at && joined_at.to_date > date
    return false if left_at && left_at.to_date < date

    true
  end

  def fetch_students_in_specific_recovery(differentiated = nil)
    students = []

    recovery_steps = RecoveryStepsFetcher.new(step, classroom).fetch

    recovery_exam_rule = classroom_grades_with_recovery_rule.first.exam_rule.recovery_exam_rules.find { |recovery_diary_record|
      recovery_diary_record.steps.last.eql?(@step.to_number)
    }

    if recovery_exam_rule.present?
      students = filter_students_in_recovery.select { |student|
        sum_averages = 0
        
        recovery_steps.each do |step|
          average = student.average(classroom, discipline, step)
          sum_averages += average.to_f
        end

        average = sum_averages / recovery_steps.count

        average < recovery_exam_rule.average
      }
    end

    filter_differentiated_students(students, differentiated)
  end

  def filter_differentiated_students(students, differentiated)
    if differentiated == !!differentiated
      students = students.select do |student|
        student.uses_differentiated_exam_rule == differentiated
      end
    end

    students
  end
end
