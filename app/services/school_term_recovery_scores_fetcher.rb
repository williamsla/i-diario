class SchoolTermRecoveryScoresFetcher
  def self.recovery_step_for(classroom, semester_steps)
    return if semester_steps.blank?

    exam_rule = classroom.first_exam_rule_with_recovery
    if exam_rule&.recovery_type == RecoveryTypes::SPECIFIC && exam_rule.recovery_exam_rules.any?
      semester_numbers = semester_steps.map(&:to_number)
      matching_rule = exam_rule.recovery_exam_rules
        .select { |rule| semester_numbers.any? { |number| rule.steps.last.eql?(number) } }
        .max_by { |rule| rule.steps.last.to_i }

      if matching_rule
        return semester_steps.find { |step| matching_rule.steps.last.eql?(step.to_number) } ||
               semester_steps.last
      end
    end

    semester_steps.last
  end

  def initialize(classroom, discipline, steps)
    @classroom = classroom
    @discipline = discipline
    @steps = Array(steps).compact
  end

  def score_for(student_id, step)
    return if step.blank?

    scores.dig(student_id, step.step_number)
  end

  def scores
    @scores ||= load_scores
  end

  private

  attr_reader :classroom, :discipline

  def load_scores
    return {} if @steps.blank?

    records = SchoolTermRecoveryDiaryRecord
      .includes(recovery_diary_record: :students)
      .by_classroom_id(classroom.id)
      .by_discipline_id(discipline.id)
      .where(step_number: @steps.map(&:step_number).uniq)

    result = {}
    records.each do |record|
      next if record.recovery_diary_record.blank?

      record.recovery_diary_record.students.each do |student|
        result[student.student_id] ||= {}
        result[student.student_id][record.step_number] = student.score
      end
    end
    result
  end
end
