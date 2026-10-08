# Intervalos de enturmação do aluno na turma.
#
# O relatório de frequência lista só a enturmação mais recente de cada aluno.
# Depois de uma transferência e um retorno, essa enturmação tem o joined_at do
# retorno, e o período da enturmação anterior aparecia como não enturmado.
class StudentEnrollmentDateRanges
  def self.for(classroom_id:, student_ids:, period: nil)
    new(classroom_id, student_ids, period)
  end

  def initialize(classroom_id, student_ids, period = nil)
    @ranges_by_student_id = Hash.new { |ranges, student_id| ranges[student_id] = [] }
    return if classroom_id.blank? || student_ids.blank?

    scope = StudentEnrollmentClassroom.by_classroom(classroom_id)
                                      .by_student(student_ids)
                                      .includes(:student_enrollment)
    scope = scope.by_period(period) if period.present? && period.to_s != Periods::FULL.to_s

    scope.each do |enrollment_classroom|
      joined_at = parse_date(enrollment_classroom.joined_at)
      next if joined_at.nil?

      student_id = enrollment_classroom.student_enrollment.student_id
      @ranges_by_student_id[student_id] << [joined_at, parse_date(enrollment_classroom.left_at)]
    end
  end

  def cover?(student_id, date)
    date = date.to_date
    @ranges_by_student_id[student_id].any? do |joined_at, left_at|
      date >= joined_at && (left_at.nil? || date < left_at)
    end
  end

  private

  def parse_date(value)
    return if value.blank?

    value.to_date
  rescue ArgumentError, TypeError
    nil
  end
end
