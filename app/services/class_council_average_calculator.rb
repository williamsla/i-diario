# Média numérica da etapa no conselho de classe.
# A conta é a mesma da coluna Etapa do relatório de avaliações numéricas:
# o tipo e o divisor vêm da configuração da etapa (TestSetting), não de uma
# quantidade fixa de avaliações.
class ClassCouncilAverageCalculator
  def initialize(student:, classroom:, discipline:, step:, student_only: false)
    @student = student
    @classroom = classroom
    @discipline = discipline
    @step = step
    @student_only = student_only
  end

  def calculate(allow_remote: true, fill_blank_from_ieducar: false)
    average = local_average
    return average unless average.nil?
    return remote_average if fill_blank_from_ieducar
    return unless allow_remote
    return if diary_in_classroom?

    remote_average
  end

  def self.average_for(test_setting:, score_sum:, scores_count:, weight_sum:)
    if test_setting.sum_calculation_type?
      score_sum / test_setting.default_division_weight
    elsif test_setting.arithmetic_and_sum_calculation_type?
      return if weight_sum.blank?
      return if weight_sum.to_d <= 0

      # Somatório com pesos livres, normalizado para a escala 0..10.
      score_sum / (weight_sum / 10.to_d)
    else
      scores_count.zero? ? 0 : score_sum / scores_count
    end
  end

  private

  def local_average
    StudentAverageCalculator.new(@student).calculate(
      @classroom,
      @discipline,
      @step,
      **calculator_options(ieducar_fallback: false)
    )
  end

  def remote_average
    StudentAverageCalculator.new(@student).calculate(
      @classroom,
      @discipline,
      @step,
      **calculator_options
    )
  end

  def calculator_options(extra = {})
    extra[:student_only] = true if @student_only
    extra
  end

  # Aluno que já tem diário nesta turma não recebe nota de outra origem
  # numa etapa que o professor deixou sem avaliação.
  def diary_in_classroom?
    student_id = @student.id
    classroom_id = @classroom.id

    DailyNoteStudent.by_student_id(student_id).by_classroom_id(classroom_id).where.not(note: nil).exists? ||
      ConceptualExam.by_student_id(student_id).by_classroom_id(classroom_id)
        .joins(:conceptual_exam_values)
        .where.not(conceptual_exam_values: { value: nil })
        .exists? ||
      RecoveryDiaryRecordStudent.joins(:recovery_diary_record)
        .where(student_id: student_id, recovery_diary_records: { classroom_id: classroom_id })
        .where.not(score: nil)
        .exists?
  end
end
