# frozen_string_literal: true

class ConceptualExamReportBatchBuilder
  def initialize(entity_configuration:, unity:, classroom:, teacher_id:, start_at:, end_at:)
    @entity_configuration = entity_configuration
    @unity = unity
    @classroom = classroom
    @teacher_id = teacher_id
    @start_at = start_at.to_date
    @end_at = end_at.to_date
  end

  def each_rendered_report
    return enum_for(:each_rendered_report) unless block_given?
    return unless classroom_has_conceptual_score_type?

    steps_in_range.each do |step|
      data = ConceptualExamReportDataFetcher.new(
        classroom: classroom,
        step: step,
        teacher_id: teacher_id
      ).call
      next unless data.reportable?

      pdf_report = ConceptualExamReport.build(
        entity_configuration,
        unity,
        classroom,
        step,
        data.students,
        data.disciplines,
        data.conceptual_exams_by_student
      )

      yield pdf_report.render, step
    end
  end

  def self.classroom_has_conceptual_score_type?(classroom)
    classroom.classrooms_grades.any? do |classrooms_grade|
      exam_rule = classrooms_grade.exam_rule
      next false if exam_rule.blank?

      [ScoreTypes::CONCEPT, ScoreTypes::NUMERIC_AND_CONCEPT].include?(exam_rule.score_type)
    end
  end

  private

  attr_reader :entity_configuration, :unity, :classroom, :teacher_id, :start_at, :end_at

  def classroom_has_conceptual_score_type?
    self.class.classroom_has_conceptual_score_type?(classroom)
  end

  def steps_in_range
    StepsFetcher.new(classroom)
      .steps_by_date_range(start_at, end_at)
      .ordered
  end
end
