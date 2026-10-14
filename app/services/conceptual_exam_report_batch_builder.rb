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

    payload = concepts_by_discipline
    return if payload[:disciplines].blank?

    pdf_report = ConceptualExamByDisciplineReport.build(
      entity_configuration,
      unity,
      classroom,
      payload[:columns],
      payload[:disciplines],
      payload[:students_by_discipline_id],
      payload[:concepts]
    )

    yield pdf_report.render
  end

  def self.classroom_has_conceptual_score_type?(classroom)
    return true if classroom.classrooms_grades.any? { |classrooms_grade|
      conceptual_rule?(classrooms_grade.exam_rule) ||
        conceptual_rule?(classrooms_grade.exam_rule&.differentiated_exam_rule)
    }

    TeacherDisciplineClassroom.by_classroom(classroom.id).by_score_type(ScoreTypes::CONCEPT).exists? ||
      ConceptualExam.by_classroom(classroom.id).exists?
  end

  def self.conceptual_rule?(exam_rule)
    return false if exam_rule.blank?

    [ScoreTypes::CONCEPT, ScoreTypes::NUMERIC_AND_CONCEPT].include?(exam_rule.score_type)
  end

  private

  attr_reader :entity_configuration, :unity, :classroom, :teacher_id, :start_at, :end_at

  def classroom_has_conceptual_score_type?
    self.class.classroom_has_conceptual_score_type?(classroom)
  end

  def steps_in_range
    fetcher = StepsFetcher.new(classroom)
    ranged = fetcher.steps_by_date_range(start_at, end_at)
    ranged = ranged.ordered if ranged.respond_to?(:ordered)
    return ranged if ranged.present?

    fetcher.steps
  end

  def concepts_by_discipline
    steps = Array(steps_in_range)
    annual = GeneralConfiguration.annual_conceptual_evaluation?
    disciplines = {}
    students_by_discipline_id = Hash.new { |hash, key| hash[key] = {} }
    concepts = {}

    steps.each do |step|
      data = ConceptualExamReportDataFetcher.new(
        classroom: classroom,
        step: step,
        teacher_id: teacher_id
      ).call
      next unless data.reportable?

      data.disciplines.each do |discipline|
        disciplines[discipline.id] = discipline
        data.students.each do |student|
          students_by_discipline_id[discipline.id][student.id] = student
        end
      end

      step_key = annual ? nil : step.step_number
      data.conceptual_exams_by_student.each do |student_id, exam|
        next if exam.blank?

        exam.conceptual_exam_values.each do |value|
          next if value.value.nil?

          concepts[[student_id, value.discipline_id, step_key]] = value.value
        end
      end
    end

    columns = if annual
                [{ label: 'Conceito', key: nil }]
              else
                steps.map { |step| { label: step.school_term, key: step.step_number } }
              end

    ordered_disciplines = disciplines.values.sort_by { |discipline|
      [
        discipline.knowledge_area&.sequence.to_i,
        discipline.knowledge_area&.description.to_s,
        discipline.sequence.to_i,
        discipline.description.to_s
      ]
    }

    {
      columns: columns,
      disciplines: ordered_disciplines,
      students_by_discipline_id: students_by_discipline_id.transform_values { |students|
        students.values.sort_by { |student| student.name.to_s }
      },
      concepts: concepts
    }
  end
end
