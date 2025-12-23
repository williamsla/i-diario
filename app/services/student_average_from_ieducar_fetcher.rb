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

    result = api.fetch(
      aluno_id: student.api_code,
      turma_id: classroom.api_code,
      componente_curricular_id: discipline.api_code,
      etapa: step_number
    )

    # A API pode retornar a média em diferentes formatos
    # Tentar diferentes chaves possíveis
    media = result['media'] || result['nota'] || result['media_geral']
    
    if media.present?
      media.to_f
    elsif result.is_a?(Array) && result.first.present?
      # Se retornar um array, pegar o primeiro elemento
      media_from_array = result.first['media'] || result.first['nota'] || result.first['media_geral']
      media_from_array.present? ? media_from_array.to_f : nil
    else
      nil
    end
  rescue IeducarApi::Base::ApiError => error
    Rails.logger.error "Erro ao buscar média do i-educar: #{error.message}"
    nil
  rescue StandardError => error
    Rails.logger.error "Erro inesperado ao buscar média do i-educar: #{error.message}"
    nil
  end

  private

  def api
    IeducarApi::StudentAverages.new(@ieducar_api_configuration.to_api)
  end
end

