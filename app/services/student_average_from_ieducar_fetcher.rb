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

    # Buscar a matrícula (StudentEnrollment) do aluno na turma
    student_enrollment = StudentEnrollment
      .by_student(student_id)
      .by_classroom(classroom_id)
      .first

    return nil if student_enrollment.blank? || student_enrollment.api_code.blank?

    result = api.fetch(
      registration_id: student_enrollment.api_code,
      discipline_id: discipline.api_code,
      stage: step_number
    )

    logger.info "Result: #{result.inspect}"

    # A API retorna: {"message"=>"...", "data"=>{"stage"=>1, "score"=>"7.5", ...}}
    # ou {"message"=>"...", "data"=>[{"stage"=>1, "score"=>"7.5", ...}]} (array)
    return nil unless result.is_a?(Hash) && result['data'].present?

    # Se data for um array, busca a etapa específica (compatibilidade com versões antigas)
    stage_data = if result['data'].is_a?(Array)
                   result['data'].find { |item| item['stage'] == step_number }
                 else
                   result['data']
                 end

    return nil unless stage_data.present?

    # Prioridade: recovery_specific_score > recovery_parallel_score > score
    score = stage_data['recovery_specific_score'] || 
            stage_data['recovery_parallel_score'] || 
            stage_data['score']

    return nil if score.blank?

    score.to_f
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

