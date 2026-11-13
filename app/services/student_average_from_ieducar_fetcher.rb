class StudentAverageFromIeducarFetcher
  def initialize(ieducar_api_configuration)
    @ieducar_api_configuration = ieducar_api_configuration
  end

  def fetch(student_id, classroom_id, discipline_id, step_number)
    return nil unless @ieducar_api_configuration.present?

    student = Student.find(student_id)
    classroom = Classroom.find(classroom_id)
    discipline = Discipline.find(discipline_id)

    return nil if student.api_code.blank? || classroom.api_code.blank? || discipline.api_code.blank?

    # Da matrícula mais recente para a primeira. A nota vazia na última
    # matrícula é preenchida pela matrícula anterior do mesmo aluno.
    StudentClassroomEnrollments.for_student(student_id, classroom_id).reverse_each do |student_enrollment|
      score = score_for_enrollment(student_enrollment, discipline.api_code, step_number)
      return score if score.present?
    end

    nil
  rescue IeducarApi::Base::ApiError => error
    logger.error "Erro ao buscar média do i-educar: #{error.message}"
    logger.error "Backtrace: #{error.backtrace.join("\n")}" if error.backtrace
    nil
  rescue StandardError => error
    logger.error "Erro inesperado ao buscar média do i-educar: #{error.message}"
    logger.error "Backtrace: #{error.backtrace.join("\n")}" if error.backtrace
    nil
  end

  private

  def score_for_enrollment(student_enrollment, discipline_api_code, step_number)
    return nil if student_enrollment.blank? || student_enrollment.api_code.blank?

    records = discipline_records(student_enrollment, discipline_api_code)
    if records.nil?
      result = api.fetch(
        registration_id: student_enrollment.api_code,
        discipline_id: discipline_api_code,
        stage: step_number
      )
      logger.info "Result: #{result.inspect}"
      return nil unless result.is_a?(Hash) && result['data'].present?

      records = result['data'].is_a?(Array) ? result['data'] : [result['data']]
    end

    score_from(stage_record_for(records, step_number))
  rescue IeducarApi::Base::ApiError, StandardError => error
    logger.error "Erro ao buscar média da matrícula #{student_enrollment.api_code}: #{error.message}"
    nil
  end

  def discipline_records(student_enrollment, discipline_api_code)
    ReportQueryCache.fetch([:ieducar_student_scores, student_enrollment.api_code, discipline_api_code]) do
      api.fetch_by_discipline(
        registration_id: student_enrollment.api_code,
        discipline_id: discipline_api_code
      )
    end
  end

  def score_from(stage_data)
    return nil unless stage_data.present?

    # Prioridade: recovery_specific_score > recovery_parallel_score > score
    score = stage_data['recovery_specific_score'] ||
            stage_data['recovery_parallel_score'] ||
            stage_data['score']

    return nil if score.blank?

    score.to_f
  end

  def stage_record_for(data, step_number)
    records = data.is_a?(Array) ? data : [data]
    records.find { |item| same_stage?(item, step_number) }
  end

  def same_stage?(item, step_number)
    return false unless item.is_a?(Hash)

    stage = item['stage']
    return false if stage.blank? || step_number.blank?

    stage.to_i == step_number.to_i
  end

  def api
    IeducarApi::StudentAverages.new(@ieducar_api_configuration.to_api)
  end

  def logger
    @logger ||= begin
      log_file = Rails.root.join('log', 'student_average_from_ieducar.log')
      logger = Logger.new(log_file, 'daily')
      logger.level = Logger::INFO
      logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} -- #{msg}\n"
      end
      logger
    end
  end
end

