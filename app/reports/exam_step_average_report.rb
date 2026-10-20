require 'action_view'

class ExamStepAverageReport < BaseReport
  include ActionView::Helpers::NumberHelper

  STUDENT_BY_PAGE_COUNT = 45
  SOCIAL_NAME_REDUCTION_FACTOR = 3

  STATUS_LABELS = {
    StudentEnrollmentStatus::APPROVED => 'Aprovado',
    StudentEnrollmentStatus::REPPROVED => 'Reprovado',
    StudentEnrollmentStatus::STUDYING => 'Cursando',
    StudentEnrollmentStatus::TRANSFERRED => 'Transferido',
    StudentEnrollmentStatus::RECLASSIFIED => 'Reclassificado',
    StudentEnrollmentStatus::ABANDONMENT => 'Abandono',
    StudentEnrollmentStatus::APPROVED_WITH_DEPENDENCY => 'Aprovado c/ dep.',
    StudentEnrollmentStatus::APPROVE_BY_COUNCIL => 'Apr. conselho',
    StudentEnrollmentStatus::DISAPPROVED_BY_FAULTS => 'Rep. faltas',
    StudentEnrollmentStatus::DECEASED => 'Óbito'
  }.freeze

  def self.build(entity_configuration, unity, teacher, year, classroom, discipline, steps, students_enrollments)
    new(:portrait).build(entity_configuration, unity, teacher, year, classroom, discipline, steps, students_enrollments)
  end

  def build(entity_configuration, unity, teacher, year, classroom, discipline, steps, students_enrollments)
    @entity_configuration = entity_configuration
    @unity = unity
    @teacher = teacher
    @year = year
    @classroom = classroom
    @discipline = discipline
    @steps = steps
    @students_enrollments = students_enrollments
    @active_search = false

    header
    content
    footer

    self
  end

  protected

  attr_accessor :any_student_with_dependence

  private

  def classroom
    @classroom
  end

  def discipline
    @discipline
  end

  def header
    exam_header = make_cell(content: evaluation_sheet_title, size: 12, font_style: :bold, background_color: 'DEDEDE', height: 20, padding: [2, 2, 4, 4], align: :center, colspan: 5)
    begin
      logo_cell = make_cell(image: entity_logo_io, fit: [50, 50], width: 70, rowspan: 4, position: :center, vposition: :center)
    rescue
      logo_cell = make_cell(content: '', width: 70, rowspan: 4)
    end

    entity_name = @entity_configuration ? @entity_configuration.entity_name : ''
    organ_name = @entity_configuration ? @entity_configuration.organ_name : ''

    entity_organ_and_unity_cell = make_cell(content: "#{entity_name}\n#{organ_name}\n#{@unity.name}", size: 10, leading: 1.5, align: :center, valign: :center, rowspan: 4, width: 300, padding: [4, 2, 8, 2])
    classroom_header = make_cell(content: 'Turma', size: 8, font_style: :bold, colspan: 2, borders: [:top, :left, :right], padding: [2, 2, 4, 4], height: 2)
    year_header = make_cell(content: 'Ano letivo', size: 8, font_style: :bold, borders: [:top, :left, :right], padding: [2, 2, 4, 4], height: 2)
    teacher_header = make_cell(content: 'Professor(a)', size: 8, font_style: :bold, colspan: 3, borders: [:top, :left, :right], padding: [2, 2, 4, 4])
    classroom_cell = make_cell(content: classroom.description, size: 10, colspan: 2, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], height: 4)
    year_cell = make_cell(content: @year.to_s, size: 10, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4], height: 4)
    teacher_cell = make_cell(content: @teacher.name, size: 10, colspan: 3, borders: [:bottom, :left, :right], padding: [0, 2, 4, 4])
    discipline_header = make_cell(content: 'Disciplina', size: 8, font_style: :bold, colspan: 1, rowspan: 1, borders: [:top, :bottom, :left], padding: [2, 2, 4, 4])
    discipline_cell = make_cell(content: (discipline ? discipline.description : 'Geral'), size: 10, colspan: 4, borders: [:top, :bottom, :right], padding: [0, 2, 4, 4])

    first_table_data = [[exam_header],
                        [logo_cell, entity_organ_and_unity_cell, classroom_header, year_header],
                        [classroom_cell, year_cell],
                        [teacher_header],
                        [teacher_cell],
                        [discipline_header, discipline_cell]]

    page_header do
      table(first_table_data, width: bounds.width, header: true) do
        cells.border_width = 0.25
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end
    end
  end

  def data_table
    return data_table_semestral if semestral_recovery_sheet?

    students = {}
    conceptual_exams_by_student_and_step = load_conceptual_exams_by_student_and_step
    step_recovery_scores = load_step_recovery_scores
    final_recovery_scores = load_final_recovery_scores

    recovery_exam_rule = classroom.first_exam_rule_with_recovery.try(:recovery_exam_rules).try(:first)
    recovery_average = recovery_exam_rule.try(:average) || 0

    @students_enrollments.each do |student_enrollment|
      student = student_enrollment.student
      uses_conceptual = student_uses_conceptual_evaluation?(student)

      students[student_enrollment.id] = {
        name: student.to_s,
        social_name: student.social_name,
        student_id: student.id,
        dependence: false,
        uses_conceptual: uses_conceptual,
        status_code: student_enrollment.status,
        scores: [],
        scores_number: [],
        recoveries: [],
        scores_with_recovery: []
      }

      @steps.each do |school_calendar_step|
        score = if uses_conceptual
                  conceptual_exam = conceptual_exams_by_student_and_step[[student.id, school_calendar_step.step_number]]
                  fetch_conceptual_score_from_exam(student, conceptual_exam)
                else
                  StudentAverageCalculator.new(student).calculate(classroom, discipline, school_calendar_step)
                end

        recovery_score = uses_conceptual ? nil : step_recovery_scores[[student.id, school_calendar_step.step_number]]

        students[student_enrollment.id][:scores_number] << score
        students[student_enrollment.id][:recoveries] << recovery_score
        students[student_enrollment.id][:scores] << score_cell(score, school_calendar_step, uses_conceptual, recovery_average)
        students[student_enrollment.id][:scores] << recovery_cell(recovery_score)

        unless uses_conceptual
          recovery_for_calc = if recovery_score.present?
                                calculate_recovery_score(student.id, recovery_score, school_calendar_step)
                              end
          average_with_recovery = SchoolTermAverageCalculator.new(classroom).calculate(score, recovery_for_calc)
          students[student_enrollment.id][:scores_with_recovery] << average_with_recovery
        end
      end

      final_recovery = uses_conceptual ? nil : final_recovery_scores[student.id]
      students[student_enrollment.id][:final_recovery] = final_recovery
      students[student_enrollment.id][:final_average] = if uses_conceptual
                                                          nil
                                                        else
                                                          calculate_final_average(
                                                            students[student_enrollment.id][:scores_with_recovery],
                                                            final_recovery
                                                          )
                                                        end
      students[student_enrollment.id][:status] = enrollment_status_label(
        students[student_enrollment.id][:status_code],
        students[student_enrollment.id][:final_average],
        recovery_average,
        final_recovery
      )
    end

    headers = build_table_headers
    students_cells = build_students_cells(students)

    sliced_students_cells = students_cells.each_slice(student_slice_size(students)).to_a

    sliced_students_cells.each_with_index do |students_cells_slice, index|
      data = [headers] + students_cells_slice

      page_content do
        table(data, row_colors: ['FFFFFF', 'DEDEDE'], cell_style: { size: 7, padding: [2, 1, 2, 1], inline_format: true }, width: bounds.width) do |t|
          t.cells.border_width = 0.25
          t.before_rendering_page do |page|
            page.row(0).border_top_width = 0.25
            page.row(-1).border_bottom_width = 0.25
            page.column(0).border_left_width = 0.25
            page.column(-1).border_right_width = 0.25
          end
        end
      end

      start_new_page if index < sliced_students_cells.count - 1
    end
  end

  def semestral_recovery_sheet?
    GeneralConfiguration.semestral_recovery? && @steps.size > 1 && !classroom_without_numeric_score?
  end

  def footer_legend
    recovery_label = if semestral_recovery_sheet?
                       'Rec = Recuperação do semestre'
                     else
                       'Rec = Recuperação parcial da etapa'
                     end

    "Legendas: #{recovery_label} | Situação conforme matrícula no i-Educar"
  end

  # Recuperação semestral: a nota da recuperação compõe a média das etapas do semestre,
  # (média parcial + recuperação) / 2, quando a recuperação é maior que a média parcial.
  def data_table_semestral
    conceptual_exams_by_student_and_step = load_conceptual_exams_by_student_and_step
    final_recovery_scores = load_final_recovery_scores
    groups = semestral_step_groups
    recovery_scores = semestral_recovery_scores(groups)
    promotion_average = recovery_rule_average

    students = {}
    @students_enrollments.each do |student_enrollment|
      student = student_enrollment.student
      uses_conceptual = student_uses_conceptual_evaluation?(student)
      step_scores = []

      @steps.each do |step|
        step_scores << if uses_conceptual
                         conceptual_exam = conceptual_exams_by_student_and_step[[student.id, step.step_number]]
                         fetch_conceptual_score_from_exam(student, conceptual_exam)
                       else
                         StudentAverageCalculator.new(student).calculate(classroom, discipline, step)
                       end
      end

      final_recovery = uses_conceptual ? nil : final_recovery_scores[student.id]
      summary = if uses_conceptual
                  empty_semestral_summary(groups)
                else
                  semestral_summary(step_scores, recovery_scores, student.id, groups, final_recovery)
                end

      students[student_enrollment.id] = {
        name: student.to_s,
        social_name: student.social_name,
        dependence: false,
        cells: semestral_score_cells(step_scores, summary, groups, uses_conceptual, promotion_average) + [
          make_cell(
            content: enrollment_status_label(
              student_enrollment.status,
              summary[:final_average],
              promotion_average,
              final_recovery
            ).to_s,
            align: :center,
            size: 6
          )
        ]
      }
    end

    render_score_table(semestral_headers(groups), build_semestral_rows(students), students)
  end

  def semestral_step_groups
    if @steps.size == 2
      [{
        steps: @steps,
        label: :single,
        recovery_step: SchoolTermRecoveryScoresFetcher.recovery_step_for(classroom, @steps),
        fallback_recovery_step: SchoolTermRecoveryScoresFetcher.recovery_step_for(classroom, [@steps.first])
      }]
    else
      total = @steps.size
      first_count = (total.to_f / 2).ceil
      first_steps = @steps.first(first_count)
      second_steps = @steps.last(total - first_count)

      [
        {
          steps: first_steps,
          label: :first,
          recovery_step: SchoolTermRecoveryScoresFetcher.recovery_step_for(classroom, first_steps)
        },
        {
          steps: second_steps,
          label: :second,
          recovery_step: SchoolTermRecoveryScoresFetcher.recovery_step_for(classroom, second_steps)
        }
      ].reject { |group| group[:steps].blank? }
    end
  end

  def semestral_recovery_scores(groups)
    steps = groups.flat_map { |group| [group[:recovery_step], group[:fallback_recovery_step]] }
    SchoolTermRecoveryScoresFetcher.new(classroom, discipline, steps)
  end

  def semestral_summary(step_scores, recovery_scores, student_id, groups, final_recovery)
    offset = 0
    semester_finals = []
    columns = groups.map do |group|
      values = step_scores.slice(offset, group[:steps].size) || []
      offset += group[:steps].size
      partial_raw = if values.empty?
                      nil
                    else
                      values.map { |value| value.to_f }.sum / values.size.to_f
                    end
      recovery = semester_recovery_score(recovery_scores, student_id, group)
      final_raw = apply_semester_recovery(partial_raw, recovery)
      semester_finals << final_raw

      {
        partial: round_semestral_score(partial_raw),
        recovery: recovery,
        average: round_semestral_score(final_raw)
      }
    end

    year_raw = if groups.size == 1
                 semester_finals.first
               else
                 rounded_semesters = semester_finals.map { |value| round_semestral_score(value) || 0 }
                 rounded_semesters.sum.to_f / rounded_semesters.size
               end
    final_raw = year_raw
    if final_recovery.present? && year_raw.present? && final_recovery.to_f > year_raw.to_f
      final_raw = (final_recovery.to_f + year_raw.to_f) / 2.0
    end

    {
      columns: columns,
      final_recovery: final_recovery,
      final_average: round_semestral_score(final_raw)
    }
  end

  def empty_semestral_summary(groups)
    {
      columns: groups.map { { partial: nil, recovery: nil, average: nil } },
      final_recovery: nil,
      final_average: nil
    }
  end

  def semester_recovery_score(recovery_scores, student_id, group)
    score = recovery_scores.score_for(student_id, group[:recovery_step])
    return score if score.present? || group[:fallback_recovery_step].blank?

    recovery_scores.score_for(student_id, group[:fallback_recovery_step])
  end

  def apply_semester_recovery(average, recovery_score)
    return average if average.blank? || recovery_score.blank?
    return (average.to_f + recovery_score.to_f) / 2.0 if recovery_score.to_f > average.to_f

    average
  end

  def round_semestral_score(score)
    return nil if score.nil?

    ScoreRounder.new(classroom, RoundedAvaliations::NUMERICAL_EXAM, @steps.last).round(score)
  end

  def recovery_rule_average
    rule = classroom.first_exam_rule_with_recovery.try(:recovery_exam_rules).try(:first)
    rule.try(:average) || 0
  end

  def semestral_score_cells(step_scores, summary, groups, uses_conceptual, promotion_average)
    cells = []
    offset = 0

    groups.each_with_index do |group, index|
      group[:steps].each_with_index do |step, step_index|
        cells << score_cell(step_scores[offset + step_index], step, uses_conceptual, promotion_average)
      end
      offset += group[:steps].size

      column = summary[:columns][index]
      cells << semestral_numeric_cell(column[:partial], 'F0F0F0')
      cells << semestral_numeric_cell(column[:recovery], 'F0F0F0')
      cells << semestral_numeric_cell(column[:average], 'D0D0D0', bold: true)
    end

    cells << semestral_numeric_cell(summary[:final_recovery], 'D0D0D0')
    cells << semestral_numeric_cell(summary[:final_average], 'B0B0B0', bold: true)
    cells
  end

  def semestral_numeric_cell(value, background, bold: false)
    options = {
      content: localize_score(value),
      align: :center,
      background_color: background
    }
    options[:font_style] = :bold if bold
    make_cell(options)
  end

  def semestral_headers(groups)
    headers = [
      make_cell(content: 'Nº', size: 7, font_style: :bold, background_color: 'FFFFFF', align: :center, width: 15),
      make_cell(content: 'Nome do aluno', size: 7, font_style: :bold, background_color: 'FFFFFF', align: :center)
    ]

    groups.each do |group|
      group[:steps].each do |step|
        headers << make_cell(
          content: "#{step.step_number}ª Etapa",
          size: 7,
          font_style: :bold,
          background_color: 'FFFFFF',
          align: :center,
          width: 28
        )
      end
      headers.concat(semester_summary_headers(group))
    end

    headers << make_cell(content: "Rec.\nFinal", size: 7, font_style: :bold, background_color: 'D0D0D0', align: :center, valign: :center, width: 30)
    headers << make_cell(content: "Média\nFinal", size: 7, font_style: :bold, background_color: 'B0B0B0', align: :center, valign: :center, width: 30)
    headers << make_cell(content: 'Situação', size: 7, font_style: :bold, background_color: 'FFFFFF', align: :center, width: 46)
    headers
  end

  def semester_summary_headers(group)
    labels = case group[:label]
             when :single
               ["MP\nSemestre", "Rec\nSemestre", "Média\nSemestre"]
             when :first
               ["MP\n1º Sem", "Rec.\n1º Sem", "Média\n1º Sem"]
             else
               ["MP\n2º Sem", "Rec\n2º Sem", "Média\n2º Sem"]
             end
    colors = ['F0F0F0', 'F0F0F0', 'D0D0D0']

    labels.zip(colors).map do |label, color|
      make_cell(
        content: label,
        size: 7,
        font_style: :bold,
        background_color: color,
        align: :center,
        valign: :center,
        width: 32
      )
    end
  end

  def build_semestral_rows(students)
    rows = []
    sequence = 1

    students.each_value do |value|
      name_content = (value[:dependence] ? '* ' : '') + value[:name]
      rows << [make_cell(content: sequence.to_s, align: :center), { content: name_content }].concat(value[:cells])
      sequence += 1
    end

    rows
  end

  def render_score_table(headers, students_cells, students)
    sliced_students_cells = students_cells.each_slice(student_slice_size(students)).to_a

    sliced_students_cells.each_with_index do |students_cells_slice, index|
      data = [headers] + students_cells_slice

      page_content do
        table(data, row_colors: ['FFFFFF', 'DEDEDE'], cell_style: { size: 7, padding: [2, 1, 2, 1], inline_format: true }, width: bounds.width) do |t|
          t.cells.border_width = 0.25
          t.before_rendering_page do |page|
            page.row(0).border_top_width = 0.25
            page.row(-1).border_bottom_width = 0.25
            page.column(0).border_left_width = 0.25
            page.column(-1).border_right_width = 0.25
          end
        end
      end

      start_new_page if index < sliced_students_cells.count - 1
    end
  end

  def build_table_headers
    sequential_number_header = make_cell(content: 'Nº', size: 7, font_style: :bold, background_color: 'FFFFFF', align: :center, width: 15)
    student_name_header = make_cell(content: 'Nome do aluno', size: 7, font_style: :bold, background_color: 'FFFFFF', align: :center)

    step_headers = []
    @steps.each do |school_calendar_step|
      step_headers << make_cell(
        content: "#{school_calendar_step.step_number}ª Etapa",
        size: 7,
        font_style: :bold,
        background_color: 'FFFFFF',
        align: :center,
        width: 32
      )
      step_headers << make_cell(
        content: "Rec #{school_calendar_step.step_number}ª",
        size: 7,
        font_style: :bold,
        background_color: 'F0F0F0',
        align: :center,
        width: 28
      )
    end

    final_recovery_header = make_cell(content: 'Rec. Final', size: 7, font_style: :bold, background_color: 'D0D0D0', align: :center, width: 32)
    average_header = make_cell(content: 'Média Final', size: 7, font_style: :bold, background_color: 'B0B0B0', align: :center, width: 32)
    status_header = make_cell(content: 'Situação', size: 7, font_style: :bold, background_color: 'FFFFFF', align: :center, width: 48)

    [sequential_number_header, student_name_header] + step_headers + [final_recovery_header, average_header, status_header]
  end

  def build_students_cells(students)
    students_cells = []
    ordered_students = students.sort_by { |(_key, value)| value[:dependence] ? 1 : 0 }
    sequence = 1
    sequence_reseted = false

    ordered_students.each do |_key, value|
      if !sequence_reseted && value[:dependence]
        sequence = 1
        sequence_reseted = true
      end

      sequence_cell = make_cell(content: sequence.to_s, align: :center)
      name_content = (value[:dependence] ? '* ' : '') + value[:name]
      student_cells = [sequence_cell, { content: name_content }].concat(value[:scores])
      student_cells << make_cell(content: localize_score(value[:final_recovery]), align: :center, background_color: 'D0D0D0')
      student_cells << make_cell(content: localize_score(value[:final_average]), align: :center, font_style: :bold, background_color: 'B0B0B0')
      student_cells << make_cell(content: value[:status].to_s, align: :center, size: 6)

      students_cells << student_cells
      sequence += 1
    end

    students_cells
  end

  def score_cell(score, school_calendar_step, uses_conceptual, recovery_average)
    if score.nil? && school_calendar_step.end_at < Date.today && !uses_conceptual
      make_cell(content: '', align: :center)
    elsif score.is_a?(Numeric) && score < recovery_average
      make_cell(content: localize_score(score), align: :center, text_color: 'FF0000')
    else
      make_cell(content: localize_score(score), align: :center)
    end
  end

  def recovery_cell(recovery_score)
    make_cell(content: localize_score(recovery_score), align: :center, background_color: 'F0F0F0')
  end

  def calculate_final_average(scores_with_recovery, final_recovery)
    numeric_scores = scores_with_recovery.select { |value| value.is_a?(Numeric) }
    return nil if numeric_scores.empty? && final_recovery.blank?

    final_average = if numeric_scores.any?
                      numeric_scores.sum.to_f / @steps.size.to_f
                    end

    if final_recovery.present? && final_recovery.to_f > (final_average || 0).to_f
      final_average = final_recovery.to_f
    end

    return nil if final_average.blank?

    ScoreRounder.new(classroom, RoundedAvaliations::NUMERICAL_EXAM, @steps.last).round(final_average)
  end

  def load_step_recovery_scores
    ReportQueryCache.fetch([:exam_step_recoveries, classroom.id, discipline.id, @steps.map(&:id)]) do
      student_ids = @students_enrollments.map(&:student_id)
      if student_ids.blank? || @steps.blank?
        {}
      else
        min_date = @steps.map(&:start_at).min
        max_date = @steps.map(&:end_at).max

        records = SchoolTermRecoveryDiaryRecord
          .joins(recovery_diary_record: :students)
          .where(recovery_diary_records: { classroom_id: classroom.id, discipline_id: discipline.id })
          .where(recovery_diary_record_students: { student_id: student_ids })
          .where('recovery_diary_records.recorded_at >= ? AND recovery_diary_records.recorded_at <= ?', min_date, max_date)
          .includes(recovery_diary_record: :students)
          .order('recovery_diary_records.recorded_at DESC')
          .to_a

        scores = {}
        records.each do |record|
          recorded_at = record.recovery_diary_record.recorded_at.to_date
          step = @steps.detect { |item| recorded_at >= item.start_at.to_date && recorded_at <= item.end_at.to_date }
          next if step.blank?

          record.recovery_diary_record.students.each do |recovery_student|
            key = [recovery_student.student_id, step.step_number]
            next if scores.key?(key)
            next if recovery_student.score.nil?

            scores[key] = recovery_student.score
          end
        end
        scores
      end
    end
  end

  def load_final_recovery_scores
    ReportQueryCache.fetch([:exam_final_recoveries, classroom.id, discipline.id, @year]) do
      student_ids = @students_enrollments.map(&:student_id)
      school_calendar = SchoolCalendar.find_by(unity_id: @unity.id, year: @year)

      if student_ids.blank? || school_calendar.blank?
        {}
      else
        records = FinalRecoveryDiaryRecord
          .joins(recovery_diary_record: :students)
          .where(recovery_diary_records: { classroom_id: classroom.id, discipline_id: discipline.id })
          .where(recovery_diary_record_students: { student_id: student_ids })
          .where(school_calendar_id: school_calendar.id)
          .includes(recovery_diary_record: :students)
          .to_a

        scores = {}
        records.each do |record|
          record.recovery_diary_record.students.each do |recovery_student|
            next if recovery_student.score.nil?
            next if scores.key?(recovery_student.student_id)

            scores[recovery_student.student_id] = recovery_student.score
          end
        end
        scores
      end
    end
  end

  def enrollment_status_label(status, final_average, recovery_average, final_recovery)
    status_code = status.to_i

    if status_code == StudentEnrollmentStatus::STUDYING &&
       recovery_average.to_f > 0 &&
       final_average.is_a?(Numeric) &&
       final_average < recovery_average.to_f &&
       final_recovery.blank?
      return 'Em exame'
    end

    STATUS_LABELS[status_code] || status.to_s.presence || 'Cursando'
  end

  def calculate_recovery_score(student_id, score, step)
    ComplementaryExamCalculator.new(
      [AffectedScoreTypes::STEP_RECOVERY_SCORE, AffectedScoreTypes::BOTH],
      student_id,
      discipline.id,
      classroom.id,
      step
    ).calculate(score)
  end

  def load_conceptual_exams_by_student_and_step
    student_ids = @students_enrollments.map(&:student_id)
    step_numbers = @steps.map(&:step_number)

    exams = ConceptualExam
      .by_classroom_id(classroom.id)
      .where(student_id: student_ids)
      .includes(:conceptual_exam_values)
      .to_a

    by_student_and_step = exams.each_with_object({}) do |exam, hash|
      hash[[exam.student_id, exam.step_number]] = exam
    end

    # Avaliação anual guarda um único conceito. Repete na coluna de cada etapa.
    return by_student_and_step unless GeneralConfiguration.annual_conceptual_evaluation?

    exams.group_by(&:student_id).each do |student_id, student_exams|
      fallback = student_exams.max_by(&:updated_at)
      next if fallback.blank?

      step_numbers.each do |step_number|
        by_student_and_step[[student_id, step_number]] ||= fallback
      end
    end

    by_student_and_step
  end

  def evaluation_sheet_title
    return 'Avaliações numéricas' if @students_enrollments.blank?

    conceptual = @students_enrollments.any? { |enrollment| student_uses_conceptual_evaluation?(enrollment.student) }
    conceptual ? 'Avaliações' : 'Avaliações numéricas'
  end

  def classroom_without_numeric_score?
    return @classroom_without_numeric_score unless @classroom_without_numeric_score.nil?

    @classroom_without_numeric_score = classroom.classrooms_grades.none? { |classrooms_grade|
      [classrooms_grade.exam_rule, classrooms_grade.exam_rule&.differentiated_exam_rule].compact.any? { |rule|
        [ScoreTypes::NUMERIC, ScoreTypes::NUMERIC_AND_CONCEPT].include?(rule.score_type)
      }
    }
  end

  def student_uses_conceptual_evaluation?(student)
    @conceptual_evaluation_by_student ||= {}
    return @conceptual_evaluation_by_student[student.id] if @conceptual_evaluation_by_student.key?(student.id)

    exam_rule = ExamRuleFetcher.fetch(classroom, student)
    result = if classroom_without_numeric_score?
               true
             elsif exam_rule.blank?
               false
             elsif exam_rule.score_type == ScoreTypes::CONCEPT
               true
             elsif exam_rule.score_type == ScoreTypes::NUMERIC_AND_CONCEPT
               teacher_score_type_for(student) == ScoreTypes::CONCEPT
             else
               false
             end

    @conceptual_evaluation_by_student[student.id] = result
  end

  # Na turma multisseriada o mesmo componente pode ser numérico numa série e
  # conceitual em outra. O vínculo precisa ser o da série do aluno.
  def teacher_score_type_for(student)
    links = teacher_discipline_links
    return if links.blank?

    grade_id = student_grade_id(student)
    link = links.find { |item| item.grade_id == grade_id } if grade_id.present?
    link ||= links.first if links.map(&:grade_id).uniq.one?
    link&.score_type
  end

  def teacher_discipline_links
    @teacher_discipline_links ||= TeacherDisciplineClassroom.where(
      classroom_id: classroom.id,
      discipline_id: discipline.id
    ).to_a
  end

  def student_grade_id(student)
    @grade_id_by_student ||= {}
    return @grade_id_by_student[student.id] if @grade_id_by_student.key?(student.id)

    @grade_id_by_student[student.id] = ClassroomsGrade.by_student_id(student.id)
                                                      .by_classroom_id(classroom.id)
                                                      .limit(1)
                                                      .pluck(:grade_id)
                                                      .first
  end

  def fetch_conceptual_score_from_exam(student, conceptual_exam)
    return nil if conceptual_exam.blank?

    value_record = conceptual_exam.conceptual_exam_values.find { |v| v.discipline_id == discipline.id }
    concept_display_name(student, value_record&.value)
  end

  def concept_display_name(student, value)
    return nil if value.blank?

    exam_rule = ExamRuleFetcher.fetch(classroom, student)
    ConceptValueMatcher.display(exam_rule&.conceptual_rounding_table, value)
  end

  def student_slice_size(students)
    student_with_social_name_count = students.count do |_key, value|
      value.present? && value[:social_name].present?
    end

    STUDENT_BY_PAGE_COUNT - (student_with_social_name_count / SOCIAL_NAME_REDUCTION_FACTOR)
  end

  def content
    data_table
  end

  def footer
    page_footer do
      repeat(:all) do
        draw_text('Assinatura do(a) professor(a):', size: 8, style: :bold, at: [0, 0])
        draw_text('________________________________', size: 8, at: [0, 8])

        draw_text('Assinatura do(a) coordenador(a):', size: 8, style: :bold, at: [259, 0])
        draw_text('________________________________', size: 8, at: [259, 8])

        draw_text('Data:', size: 8, style: :bold, at: [450, 34])
        draw_text('________________', size: 8, at: [472, 34])
        draw_text(footer_legend, size: 7, style: :bold, at: [0, 34])
        draw_text('* Alunos cursando dependência', size: 8, at: [0, 24]) if self.any_student_with_dependence
      end
    end
  end

  def localize_score(value)
    return '' if value.blank?
    return value.to_s unless value.is_a?(Numeric)

    number_with_precision(value, precision: 1)
  end
end
