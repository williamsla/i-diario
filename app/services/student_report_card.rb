class StudentReportCard
  include ActiveSupport::NumberHelper

  def self.build(student, classroom_id: nil)
    new(student, classroom_id).build
  end

  def initialize(student, classroom_id)
    @student = student
    @classroom_id = classroom_id
  end

  def build
    return blank_card('Esta conta não está ligada a um aluno. Peça ajuda à escola.') if student.blank?
    return blank_card(no_enrollment_message) if selected_enrollment.blank?

    {
      blank: false,
      student_name: student.display_name,
      avatar_url: student.avatar_url.presence,
      school_name: classroom.unity.to_s,
      classroom_label: classroom_label(selected_enrollment),
      classroom_name: classroom.to_s,
      year: classroom.year,
      enrollments: enrollment_options,
      selected_classroom_id: classroom.id,
      frequency_message: frequency_message,
      frequency_percentage: frequency_percentage,
      frequency_low: frequency_low?,
      period_message: period_message,
      approval_message: approval_message,
      overview_message: overview_message,
      overview_label: overview_status[0],
      overview_key: overview_status[1],
      general_average: general_average_label,
      show_discipline_absences: frequency_by_discipline?,
      steps: step_payloads,
      step_labels: step_payloads.map { |step| step[:label] },
      year_rows: year_rows,
      year_opinions: year_opinions,
      year_note: unfinished_note,
      sheet: grade_sheet
    }
  end

  private

  attr_reader :student, :classroom_id

  def blank_card(message)
    { blank: true, message: message, enrollments: [] }
  end

  def no_enrollment_message
    'Ainda não encontramos uma turma para este aluno. Se a matrícula foi feita agora, peça à escola para sincronizar o sistema.'
  end

  def enrollment_classrooms
    @enrollment_classrooms ||= begin
      relation = StudentEnrollmentClassroom
                 .by_student(student.id)
                 .merge(StudentEnrollment.active)
                 .joins(classrooms_grade: :classroom)
                 .preload(classrooms_grade: [:grade, { exam_rule: [:differentiated_exam_rule, :rounding_table, :rounding_table_concept] }, { classroom: :unity }])
                 .order('classrooms.year DESC, student_enrollment_classrooms.joined_at DESC')

      current = relation.merge(StudentEnrollmentClassroom.by_date(Date.current)).to_a
      if current.any?
        current
      else
        latest_year = relation.limit(1).pluck('classrooms.year').first
        if latest_year.blank?
          []
        else
          relation.where(classrooms: { year: latest_year }).to_a
        end
      end
    end
  end

  def selected_enrollment
    @selected_enrollment ||= begin
      list = enrollment_classrooms
      if list.blank?
        nil
      else
        found = list.find { |item| item.classrooms_grade&.classroom_id.to_s == classroom_id.to_s }
        found || list.first
      end
    end
  end

  def classroom
    selected_enrollment.classrooms_grade.classroom
  end

  def classrooms_grade
    selected_enrollment.classrooms_grade
  end

  def enrollment_options
    years = enrollment_classrooms.map { |item| item.classrooms_grade&.classroom&.year }.uniq
    enrollment_classrooms.map do |item|
      label = classroom_label(item)
      year = item.classrooms_grade&.classroom&.year
      label = "#{year} · #{label}" if years.size > 1 && year.present?

      { id: item.classrooms_grade.classroom_id, label: label }
    end.uniq { |item| item[:id] }
  end

  def classroom_label(enrollment)
    grade = enrollment.classrooms_grade&.grade.to_s
    room = enrollment.classrooms_grade&.classroom.to_s
    period = enrollment.classrooms_grade&.classroom&.period_humanized
    [grade, room, period].reject(&:blank?).uniq.join(' · ')
  end

  def steps
    @steps ||= StepsFetcher.new(classroom).steps.to_a
  end

  def current_step
    @current_step ||= steps.find { |step| Date.current.between?(step.start_at, step.end_at) } ||
                      steps.select { |step| step.start_at <= Date.current }.last ||
                      steps.first
  end

  def exam_rule
    @exam_rule ||= begin
      rule = classrooms_grade&.exam_rule
      if student.uses_differentiated_exam_rule && rule&.differentiated_exam_rule.present?
        rule.differentiated_exam_rule
      else
        rule
      end
    end
  end

  def minimum_score
    exam_rule&.average_for_promotion
  end

  def frequency_by_discipline?
    exam_rule&.frequency_type.to_s == FrequencyTypes::BY_DISCIPLINE
  end

  def only_conceptual?
    exam_rule&.score_type.to_s == ScoreTypes::CONCEPT
  end

  def disciplines
    @disciplines ||= Discipline.by_classroom(classroom)
                               .not_grouper
                               .joins(:knowledge_area)
                               .where(knowledge_areas: { group_descriptors: false })
                               .order_by_sequence
                               .to_a
  end

  def step_payloads
    @step_payloads ||= begin
      payloads = steps.map do |step|
        {
          id: step.id,
          label: "#{step.to_number.to_i}ª",
          current: step == current_step,
          absence_message: step_absence_message(step),
          disciplines: disciplines.map { |discipline| discipline_payload(discipline, step) }
        }
      end
      attach_averages!(payloads)
      payloads
    end
  end

  def discipline_payload(discipline, step)
    if exempt?(discipline, step)
      return {
        name: discipline.description,
        discipline_id: discipline.id,
        step_number: step.to_number.to_i,
        score: nil,
        conceptual: false,
        score_label: '—',
        absences: nil,
        situation: 'Dispensado',
        situation_key: 'exempt',
        details: [],
        opinion: nil
      }
    end

    score = score_for(discipline, step)
    situation, situation_key = situation_for(score, discipline)

    {
      name: discipline.description,
      discipline_id: discipline.id,
      step_number: step.to_number.to_i,
      score: numeric_score?(score) ? score : nil,
      conceptual: conceptual_discipline?(discipline) || (score.present? && !numeric_score?(score)),
      score_label: score.present? ? score_label(score) : '—',
      absences: frequency_by_discipline? ? absence_count(step.start_at, step.end_at, discipline) : nil,
      situation: situation,
      situation_key: situation_key,
      details: detail_lines(discipline, step, score),
      opinion: opinion_for(discipline, step)
    }
  end

  def year_rows
    payloads = step_payloads
    return [] if payloads.blank? || payloads.first[:disciplines].blank?

    payloads.first[:disciplines].each_index.map do |index|
      rows = payloads.map { |step| step[:disciplines][index] }
      {
        name: rows.first[:name],
        scores: rows.map { |item| item[:score_label] },
        average_label: rows.first[:average_label],
        average_value: rows.first[:average_value],
        frequency_label: frequency_label(rows.first[:discipline_id]),
        frequency_detail: frequency_detail(rows.first[:discipline_id]),
        absences: frequency_by_discipline? ? rows.sum { |item| item[:absences].to_i } : nil,
        situation: rows.first[:average_situation],
        situation_key: rows.first[:average_situation_key],
        details: rows.flat_map { |row| Array(row[:details]) },
        opinions: rows.map { |row| row[:opinion] }.select(&:present?)
      }
    end
  end

  def attach_averages!(payloads)
    return if payloads.blank? || payloads.first[:disciplines].blank?

    payloads.first[:disciplines].each_index do |index|
      rows = payloads.map { |step| step[:disciplines][index] }
      label, situation, situation_key, raw = average_parts(rows)
      rows.each do |row|
        row[:average_label] = label
        row[:average_value] = raw
        row[:average_situation] = situation
        row[:average_situation_key] = situation_key
      end
    end
  end

  def average_parts(rows)
    if rows.all? { |row| row[:situation_key] == 'exempt' }
      return ['—', 'Dispensado', 'exempt', nil]
    end

    if rows.any? { |row| row[:conceptual] }
      official = official_situation
      return ['—', official[0], official[1], nil] if official

      return ['—', 'Em andamento', 'progress', nil]
    end

    counted = rows.reject { |row| row[:situation_key] == 'exempt' }
    numeric = counted.select { |row| numeric_score?(row[:score]) }
    ready = counted.present? && numeric.size == counted.size

    if ready
      raw = municipality_average(counted)
      if raw.present?
        situation, situation_key = result_situation(raw, counted.first[:discipline_id])
        return [score_label(raw), situation, situation_key, raw]
      end
    end

    return ['—', 'Em andamento', 'progress', nil] if numeric.blank?

    launched = numeric.sum { |row| row[:score].to_f } / numeric.size
    [score_label(launched), 'Em andamento', 'progress', launched]
  end

  def municipality_average(rows)
    raw = if use_semestral_average?
            semestral_year_raw(rows)
          else
            scores = rows.map { |row| adjusted_step_score(row) }
            return if scores.any?(&:nil?)

            scores.sum.to_f / scores.size
          end
    return if raw.nil?

    recovery = final_recovery_by_discipline[rows.first[:discipline_id]]
    if recovery.present? && recovery.to_f > raw.to_f
      raw = use_semestral_average? ? (recovery.to_f + raw.to_f) / 2.0 : recovery.to_f
    end

    round_average(raw)
  end

  def use_semestral_average?
    GeneralConfiguration.semestral_recovery? && steps.size > 1 && !only_conceptual?
  end

  def semestral_year_raw(rows)
    by_number = rows.index_by { |row| row[:step_number] }
    finals = semester_groups.map do |group|
      values = group.map { |step| by_number[step.to_number.to_i]&.dig(:score) }
      return if values.any?(&:blank?)

      partial = values.sum(&:to_f) / values.size
      recovery_step = SchoolTermRecoveryScoresFetcher.recovery_step_for(classroom, group)
      recovery = recovery_step && step_recovery_scores[[rows.first[:discipline_id], recovery_step.to_number.to_i]]
      apply_semester_recovery(partial, recovery)
    end
    return if finals.any?(&:nil?)

    if semester_groups.size == 1
      finals.first
    else
      rounded = finals.map { |value| round_average(value) || 0 }
      rounded.sum.to_f / rounded.size
    end
  end

  def semester_groups
    if steps.size == 2
      [steps]
    else
      first_count = (steps.size.to_f / 2).ceil
      [steps.first(first_count), steps.last(steps.size - first_count)].reject(&:blank?)
    end
  end

  def apply_semester_recovery(average, recovery_score)
    return average if average.blank? || recovery_score.blank?
    return (average.to_f + recovery_score.to_f) / 2.0 if recovery_score.to_f > average.to_f

    average
  end

  def adjusted_step_score(row)
    return if row[:score].blank?

    step = steps.find { |item| item.to_number == row[:step_number] }
    recovery = step_recovery_scores[[row[:discipline_id], row[:step_number]]]
    return row[:score] if recovery.blank? || step.blank?

    adjusted = begin
      ComplementaryExamCalculator.new(
        [AffectedScoreTypes::STEP_RECOVERY_SCORE, AffectedScoreTypes::BOTH],
        student.id,
        row[:discipline_id],
        classroom.id,
        step
      ).calculate(recovery)
    rescue StandardError
      recovery
    end

    SchoolTermAverageCalculator.new(classroom).calculate(row[:score], adjusted)
  end

  def step_recovery_scores
    @step_recovery_scores ||= SchoolTermRecoveryDiaryRecord
                              .includes(recovery_diary_record: :students)
                              .by_classroom_id(classroom.id)
                              .where(step_number: steps.map(&:to_number))
                              .each_with_object({}) do |record, hash|
      next if record.recovery_diary_record.blank?

      recovery_student = record.recovery_diary_record.students.find { |item| item.student_id == student.id }
      next if recovery_student&.score.nil?

      hash[[record.discipline_id, record.step_number.to_i]] = recovery_student.score
    end
  end

  def round_average(score)
    return if score.nil?
    return score if steps.last.blank?

    rounded = ScoreRounder.new(classroom, RoundedAvaliations::NUMERICAL_EXAM, steps.last).round(score)
    rounded.nil? ? score : rounded
  end

  def result_situation(average, discipline_id)
    official = official_situation
    return official if official
    return ['Em andamento', 'progress'] if minimum_score.blank?
    return ['Aprovado', 'approved'] if average.to_d >= minimum_score.to_d
    return ['Em recuperação', 'recovery'] if recovery_open?(discipline_id)

    ['Reprovado', 'failed']
  end

  def official_situation
    status = selected_enrollment.student_enrollment&.status.to_i

    case status
    when StudentEnrollmentStatus::APPROVED,
         StudentEnrollmentStatus::APPROVED_WITH_DEPENDENCY,
         StudentEnrollmentStatus::APPROVE_BY_COUNCIL
      ['Aprovado', 'approved']
    when StudentEnrollmentStatus::REPPROVED,
         StudentEnrollmentStatus::DISAPPROVED_BY_FAULTS
      ['Reprovado', 'failed']
    end
  end

  def recovery_open?(discipline_id)
    return false if exam_rule.blank?
    return false if exam_rule.recovery_type.to_i == RecoveryTypes::DONT_USE
    return false if final_recovery_by_discipline[discipline_id].present?

    true
  end

  def final_recovery_by_discipline
    @final_recovery_by_discipline ||= begin
      school_calendar = StepsFetcher.new(classroom).school_calendar
      if school_calendar.blank?
        {}
      else
        FinalRecoveryDiaryRecord
          .joins(recovery_diary_record: :students)
          .where(recovery_diary_records: { classroom_id: classroom.id })
          .where(recovery_diary_record_students: { student_id: student.id })
          .where(school_calendar_id: school_calendar.id)
          .includes(recovery_diary_record: :students)
          .each_with_object({}) do |record, hash|
            recovery_student = record.recovery_diary_record.students.find { |item| item.student_id == student.id }
            hash[record.discipline_id] = recovery_student&.score
          end
      end
    end
  end

  def score_for(discipline, step)
    return conceptual_score(discipline, step) if conceptual_discipline?(discipline)

    numeric_score(discipline, step)
  end

  def conceptual_discipline?(discipline)
    score_type = exam_rule&.score_type.to_s
    return true if score_type == ScoreTypes::CONCEPT
    return false unless score_type == ScoreTypes::NUMERIC_AND_CONCEPT

    teacher_score_types[[discipline.id, classrooms_grade&.grade_id]].to_s == ScoreTypes::CONCEPT ||
      teacher_score_types[discipline.id].to_s == ScoreTypes::CONCEPT
  end

  def teacher_score_types
    @teacher_score_types ||= TeacherDisciplineClassroom
                             .where(classroom_id: classroom.id, discipline_id: disciplines.map(&:id))
                             .pluck(:discipline_id, :grade_id, :score_type)
                             .each_with_object({}) do |(discipline_id, grade_id, score_type), hash|
      hash[[discipline_id, grade_id]] = score_type.to_s
      hash[discipline_id] ||= score_type.to_s
    end
  end

  def conceptual_score(discipline, step)
    exam = conceptual_exams[step.step_number]
    return if exam.blank?

    value = exam.conceptual_exam_values.find { |item| item.discipline_id == discipline.id }&.value
    ConceptValueMatcher.display(exam_rule&.conceptual_rounding_table, value)
  end

  def conceptual_exams
    @conceptual_exams ||= ConceptualExam.by_classroom_id(classroom.id)
                                        .by_student_id(student.id)
                                        .includes(:conceptual_exam_values)
                                        .index_by(&:step_number)
  end

  def numeric_score(discipline, step)
    ClassCouncilAverageCalculator.new(
      student: student,
      classroom: classroom,
      discipline: discipline,
      step: step
    ).calculate
  rescue StandardError => error
    Rails.logger.warn("Boletim do aluno #{student.id}: #{error.class} #{error.message}")
    nil
  end

  def situation_for(score, discipline)
    return ['Ainda sem nota', 'pending'] if score.blank?
    return ['Lançado', 'informed'] if conceptual_discipline?(discipline) || !numeric_score?(score)
    return ['Nota lançada', 'informed'] if minimum_score.blank?
    return ['Precisa de atenção', 'attention'] if score.to_d < minimum_score.to_d

    ['Na média', 'on_track']
  end

  def numeric_score?(score)
    score.is_a?(Numeric) || score.to_s.match?(/\A-?\d+(?:\.\d+)?\z/)
  end

  def score_label(score)
    return 'Ainda sem nota' if score.blank?
    return format_number(score) if numeric_score?(score)

    score.to_s
  end

  def detail_lines(discipline, step, step_score)
    lines = daily_note_students.select { |item|
      item.daily_note&.discipline_id == discipline.id &&
        item.avaliation&.test_date &&
        item.avaliation.test_date.between?(step.start_at, step.end_at)
    }.map { |item| evaluation_line(item) }

    lines.concat(recovery_lines(discipline, step, step_score))
    lines
  end

  def evaluation_line(daily_note_student)
    avaliation = daily_note_student.avaliation
    {
      label: avaliation.to_s,
      date: I18n.l(avaliation.test_date),
      score: evaluation_score(daily_note_student)
    }
  end

  def evaluation_score(daily_note_student)
    return 'Não fez esta avaliação' if daily_note_student.exempted?
    return 'Ainda não lançada' if daily_note_student.note.blank? && !daily_note_student.has_recovery?

    format_number(daily_note_student.recovered_note)
  rescue StandardError
    return 'Ainda não lançada' if daily_note_student.note.blank?

    format_number(daily_note_student.note)
  end

  def recovery_lines(discipline, step, step_score)
    recovery_records.select { |record|
      record.discipline_id == discipline.id &&
        record.recorded_at.present? &&
        record.recorded_at.to_date.between?(step.start_at, step.end_at) &&
        record.school_term_recovery_diary_record.present?
    }.map do |record|
      student_score = record.students.find { |item| item.student_id == student.id }&.score
      next if student_score.blank?

      sentence = "Fez recuperação e tirou #{format_number(student_score)}."
      sentence = "#{sentence} A nota desta etapa ficou #{score_label(step_score)}." if step_score.present?

      { label: sentence, date: I18n.l(record.recorded_at.to_date), score: nil }
    end.compact
  end

  def daily_note_students
    @daily_note_students ||= DailyNoteStudent.by_student_id(student.id)
                                             .by_classroom_id(classroom.id)
                                             .active
                                             .includes(daily_note: { avaliation: :discipline })
                                             .to_a
  end

  def recovery_records
    @recovery_records ||= RecoveryDiaryRecord.by_classroom_id(classroom.id)
                                             .by_student_id(student.id)
                                             .includes(:school_term_recovery_diary_record, :students)
                                             .to_a
  end

  def opinion_for(discipline, step)
    text = descriptive_rows.find { |row|
      exam = row.descriptive_exam
      exam.discipline_id == discipline.id &&
        !exam.opinion_type_by_year? &&
        exam.step_number == step.step_number
    }&.value

    clean_text(text)
  end

  def year_opinions
    descriptive_rows.select { |row| row.descriptive_exam.opinion_type_by_year? }.map do |row|
      text = clean_text(row.value)
      next if text.blank?

      {
        discipline: row.descriptive_exam.discipline&.description || 'Parecer',
        text: text
      }
    end.compact
  end

  def descriptive_rows
    @descriptive_rows ||= DescriptiveExamStudent.by_student_id(student.id)
                                                .joins(:descriptive_exam)
                                                .where(descriptive_exams: { classroom_id: classroom.id })
                                                .includes(descriptive_exam: :discipline)
                                                .to_a
  end

  def clean_text(value)
    ActionController::Base.helpers.strip_tags(value.to_s).squish.presence
  end

  def exempt?(discipline, step)
    exempted_discipline_ids(step).include?(discipline.id)
  end

  def exempted_discipline_ids(step)
    @exempted_discipline_ids ||= {}
    @exempted_discipline_ids[step.step_number] ||= StudentEnrollmentExemptedDiscipline
                                                   .by_student_enrollment(selected_enrollment.student_enrollment_id)
                                                   .by_step_number(step.step_number)
                                                   .pluck(:discipline_id)
  end

  def absence_counter
    @absence_counter ||= AbsenceCountService.new(GeneralConfiguration.current.do_not_send_justified_absence)
  end

  def absence_count(start_at, end_at, discipline = nil)
    return 0 if start_at.blank? || end_at.blank? || end_at < start_at

    absence_counter.count(student, classroom, start_at, end_at, discipline)
  end

  def frequency_stats
    @frequency_stats ||= begin
      start_at = steps.map(&:start_at).compact.min
      end_at = [steps.map(&:end_at).compact.max, Date.current].compact.min
      absences = absence_count(start_at, end_at)
      school_days = if start_at.blank? || end_at.blank? || end_at < start_at
                      0
                    else
                      UnitySchoolDay.by_unity_id(classroom.unity_id).by_date_between(start_at, end_at).count
                    end
      percentage = school_days.positive? ? ((school_days - absences).to_f / school_days * 100) : nil
      percentage = 0 if percentage&.negative?

      { absences: absences, percentage: percentage&.round, percentage_exact: percentage, school_days: school_days }
    end
  end

  def frequency_low?
    stats = frequency_stats
    stats[:percentage].present? && stats[:school_days] >= 20 && stats[:percentage] < 75
  end

  def grade_sheet
    payloads = step_payloads
    base = { status: enrollment_status_label, header: [], rows: [] }
    return base.merge(kind: 'steps') if payloads.blank? || payloads.first[:disciplines].blank?

    if use_semestral_average?
      semestral_sheet(payloads)
    else
      steps_sheet(payloads)
    end
  end

  def enrollment_status_label
    status = selected_enrollment.student_enrollment&.status.to_i
    labels = {
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
    }
    labels[status] || 'Cursando'
  end

  def semestral_sheet(payloads)
    groups = semester_groups
    header = [[header_cell('DISCIPLINA', rowspan: 2, css: 'largo')]]
    second = []

    groups.each_with_index do |group, index|
      titles = group.map { |step| step_heading(step) } + ['Rec Sem', semester_average_heading(index, groups.size)]
      header[0] << header_cell(semester_title(index, groups.size), colspan: titles.size)
      titles.each { |title| second << header_cell(title) }
    end

    ['Rec. Final', 'Média final', 'Faltas', 'Freq.%'].each do |title|
      header[0] << header_cell(title, rowspan: 2)
    end

    {
      kind: 'semestral',
      status: enrollment_status_label,
      header: [header[0], second],
      labels: column_labels([header[0], second]),
      rows: discipline_indexes(payloads).map { |index| semestral_row(payloads, index, groups) }
    }
  end

  def steps_sheet(payloads)
    general_absences = steps.map { |step| absence_count(step.start_at, step.end_at) }
    header = [[header_cell('DISCIPLINA', rowspan: 2, css: 'largo')]]
    second = []

    steps.each_with_index do |step, index|
      header[0] << header_cell(step_heading(step))
      header[0] << header_cell('F')
      second << header_cell('NOTA')
      second << header_cell(frequency_by_discipline? ? '' : general_absences[index].to_i.to_s)
    end

    header[0] << header_cell('Exame final', rowspan: 2)
    header[0] << header_cell('Média final', rowspan: 2)
    header[0] << header_cell('Faltas')
    header[0] << header_cell('Freq. %')
    second << header_cell(frequency_by_discipline? ? '' : general_absences.sum.to_s)
    second << header_cell(frequency_by_discipline? ? '' : format_percent(frequency_stats[:percentage_exact]))

    {
      kind: 'steps',
      status: enrollment_status_label,
      header: [header[0], second],
      labels: column_labels([header[0], second]),
      rows: discipline_indexes(payloads).map { |index| steps_row(payloads, index) }
    }
  end

  def semestral_row(payloads, index, groups)
    rows = payloads.map { |step| step[:disciplines][index] }
    by_number = rows.index_by { |row| row[:step_number] }
    values = []

    groups.each do |group|
      group.each do |step|
        values << grade_cell(by_number[step.to_number.to_i], step)
      end
      scores = group.map { |step| by_number[step.to_number.to_i] }
      recovery = semester_recovery_value(rows.first[:discipline_id], group)
      values << (recovery.present? ? score_label(recovery) : '')
      values << semester_average_label_for(scores, recovery)
    end

    final_recovery = final_recovery_by_discipline[rows.first[:discipline_id]]
    values << (final_recovery.present? ? score_label(final_recovery) : '')
    values << official_average_label(rows)
    values << discipline_absence_label(rows.first[:discipline_id])
    values << discipline_frequency_label(rows.first[:discipline_id])

    { name: rows.first[:name], values: values }
  end

  def steps_row(payloads, index)
    rows = payloads.map { |step| step[:disciplines][index] }
    values = []
    payloads.each_with_index do |_payload, step_index|
      row = rows[step_index]
      values << grade_cell(row, steps[step_index])
      values << (frequency_by_discipline? && row ? row[:absences].to_i.to_s : '')
    end

    final_recovery = final_recovery_by_discipline[rows.first[:discipline_id]]
    values << (final_recovery.present? ? score_label(final_recovery) : '')
    values << official_average_label(rows)
    values << (frequency_by_discipline? ? rows.sum { |row| row[:absences].to_i }.to_s : '')
    values << discipline_frequency_label(rows.first[:discipline_id])

    { name: rows.first[:name], values: values }
  end

  def discipline_indexes(payloads)
    payloads.first[:disciplines].each_index
  end

  def column_labels(header_rows)
    return [] if header_rows.blank?

    grid = []
    covered = {}
    header_rows.each_with_index do |row, row_index|
      column = 0
      row.each do |cell|
        column += 1 while covered[[row_index, column]]
        colspan = [cell[:colspan].to_i, 1].max
        rowspan = [cell[:rowspan].to_i, 1].max
        colspan.times do |offset|
          rowspan.times do |depth|
            target_column = column + offset
            if depth.zero?
              grid[row_index] ||= []
              grid[row_index][target_column] = cell[:text].to_s
            else
              covered[[row_index + depth, target_column]] = true
            end
          end
        end
        column += colspan
      end
    end

    width = grid.map { |line| line&.size.to_i }.max.to_i
    (1...width).map do |index|
      top = grid[0] && grid[0][index].to_s
      bottom = grid[1] && grid[1][index].to_s
      if bottom.present? && !header_statistic?(bottom)
        top.present? ? "#{top} · #{bottom}" : bottom
      else
        top
      end
    end
  end

  def header_statistic?(text)
    text.match?(/\A\d+(?:,\d+)?%?\z/)
  end

  def header_cell(text, colspan: 1, rowspan: 1, css: nil)
    { text: text, colspan: colspan, rowspan: rowspan, css: css }
  end

  def step_heading(step)
    description = step.respond_to?(:step_type_description) ? step.step_type_description.to_s : ''
    abbr = case description.downcase
           when /bimestre/ then 'BIM.'
           when /trimestre/ then 'TRI.'
           when /unidade/ then 'UN'
           when /semestre/ then 'SEM.'
           else description.present? ? description.split.first.to_s[0, 3].upcase : 'ET.'
           end
    mark = description.match?(/unidade|etapa/i) ? 'ª' : 'º'
    "#{step.to_number.to_i}#{mark} #{abbr}"
  end

  def semester_title(index, total)
    return 'Semestre' if total == 1

    index.zero? ? '1º Semestre' : '2º Semestre'
  end

  def semester_average_heading(index, total)
    return 'Média Final Sem' if total == 1

    index.zero? ? 'Média Final 1º Sem' : 'Média Final 2º Sem'
  end

  def semester_recovery_value(discipline_id, group)
    recovery_step = SchoolTermRecoveryScoresFetcher.recovery_step_for(classroom, group)
    return if recovery_step.blank?

    step_recovery_scores[[discipline_id, recovery_step.to_number.to_i]]
  end

  def semester_average_label_for(rows, recovery)
    return '' if rows.any?(&:blank?)

    counted = rows.reject { |row| row[:situation_key] == 'exempt' }
    return '' if counted.blank? || counted.any? { |row| row[:conceptual] }
    return '' unless counted.all? { |row| numeric_score?(row[:score]) }

    partial = counted.sum { |row| row[:score].to_f } / counted.size
    final = apply_semester_recovery(partial, recovery)
    rounded = round_average(final)
    score_label(rounded.nil? ? final : rounded)
  end

  def official_average_label(rows)
    return '' if rows.any? { |row| row[:conceptual] }

    counted = rows.reject { |row| row[:situation_key] == 'exempt' }
    return '' unless counted.present? && counted.all? { |row| numeric_score?(row[:score]) }

    raw = municipality_average(counted)
    raw.present? ? score_label(raw) : ''
  end

  def grade_cell(row, step)
    text = display_score(row)
    details = Array(row && row[:details]).map do |item|
      { date: item[:date].to_s, label: item[:label].to_s, score: item[:score].to_s }
    end
    opinion = row && row[:opinion].to_s
    discipline = row ? row[:name].to_s : ''

    {
      text: text,
      grade: true,
      discipline: discipline,
      step: step_heading(step),
      score: text,
      details: details,
      opinion: opinion.to_s,
      year_opinion: year_opinion_for(discipline)
    }
  end

  def year_opinion_for(discipline_name)
    return '' if discipline_name.blank?

    year_opinions.find { |item| item[:discipline] == discipline_name }&.dig(:text).to_s
  end

  def display_score(row)
    return '' if row.blank? || row[:situation_key] == 'exempt'
    return '' if row[:score_label].blank? || row[:score_label] == '—'

    row[:score_label]
  end

  def discipline_absence_label(discipline_id)
    stats = discipline_frequency[discipline_id]
    return '' if stats.blank?

    stats[:absences].to_i.to_s
  end

  def discipline_frequency_label(discipline_id)
    stats = discipline_frequency[discipline_id]
    return '' if stats.blank? || stats[:total].to_i.zero?

    format_percent(stats[:percentage_exact])
  end

  def format_percent(value)
    return '' if value.nil?

    number_to_rounded(value.to_d, precision: 2, strip_insignificant_zeros: false, separator: ',', delimiter: '')
  end

  def frequency_percentage
    value = frequency_stats[:percentage]
    value.present? ? "#{value}%" : '—'
  end

  def general_average_label
    rows = year_rows.reject { |row| row[:situation_key] == 'exempt' }
    return '—' if rows.blank?
    return '—' if rows.any? { |row| row[:average_value].nil? && !conceptual_row?(row) }

    values = rows.map { |row| row[:average_value] }.compact
    return '—' if values.blank?

    raw = values.sum(&:to_f) / values.size
    rounded = round_average(raw)
    score_label(rounded.nil? ? raw : rounded)
  end

  def conceptual_row?(row)
    row[:scores].any? { |score| score.present? && score != '—' && !numeric_label?(score) }
  end

  def numeric_label?(label)
    label.to_s.match?(/\A-?\d+(?:,\d+)?\z/)
  end

  def unfinished_note
    labels = unfinished_step_labels
    return if labels.blank?
    return "A #{labels.first} etapa ainda não foi encerrada." if labels.size == 1

    "As etapas #{labels.to_sentence} ainda não foram encerradas."
  end

  def unfinished_step_labels
    step_payloads.each_with_object([]) do |step, labels|
      pending = step[:disciplines].any? { |row| row[:situation_key] != 'exempt' && row[:score_label] == '—' }
      labels << step[:label] if pending
    end
  end

  def overview_status
    keys = year_rows.map { |row| row[:situation_key] } - ['exempt']
    return ['Em andamento', 'progress'] if keys.blank?
    return ['Reprovado', 'failed'] if keys.include?('failed')
    return ['Em recuperação', 'recovery'] if keys.include?('recovery')
    return ['Em andamento', 'progress'] if keys.include?('progress')
    return ['Aprovado', 'approved'] if keys.all? { |key| key == 'approved' }

    ['Em andamento', 'progress']
  end

  def frequency_message
    return 'A frequência deste ano ainda não está disponível.' if steps.blank?

    name = student.first_name.presence || 'O aluno'
    absences = frequency_stats[:absences].to_i
    sentence = if absences.zero?
                 "#{name} não faltou nenhum dia neste ano."
               else
                 "#{name} faltou #{absences} #{absences == 1 ? 'dia' : 'dias'}."
               end

    if frequency_stats[:percentage].present?
      sentence = "#{sentence} A frequência está em #{frequency_stats[:percentage]}%."
    end
    sentence = "#{sentence} A frequência está baixa. Vale conversar com a escola." if frequency_low?
    sentence
  end

  def period_message
    return 'O calendário desta turma ainda não tem períodos.' if current_step.blank?

    "Estamos em #{current_step.school_term}."
  end

  def approval_message
    messages = []
    if minimum_score.present? && !only_conceptual?
      messages << "Nesta escola, a nota para seguir bem é #{format_number(minimum_score)}."
    end
    if only_conceptual?
      messages << 'Nesta turma o boletim usa conceitos, como Bom e Ótimo.'
    elsif exam_rule&.score_type.to_s == ScoreTypes::NUMERIC_AND_CONCEPT
      messages << 'Algumas matérias usam conceitos, como Bom e Ótimo.'
    end
    messages.join(' ')
  end

  def overview_message
    keys = year_rows.map { |row| row[:situation_key] } - ['exempt']
    return 'O ano ainda está em andamento.' if keys.blank? || keys.all? { |key| key == 'progress' }
    return 'Alguma matéria está reprovada.' if keys.include?('failed')
    return 'Alguma matéria está em recuperação.' if keys.include?('recovery')
    return 'Aprovado nas matérias que já fecharam a média.' if keys.include?('approved')

    'O ano ainda está em andamento.'
  end

  def frequency_label(discipline_id)
    stats = discipline_frequency[discipline_id]
    return '—' if stats.blank? || stats[:total].to_i.zero?

    "#{stats[:percentage]}%"
  end

  def frequency_detail(discipline_id)
    stats = discipline_frequency[discipline_id]
    return if stats.blank? || stats[:total].to_i.zero?

    absences = stats[:absences].to_i
    absences == 1 ? '1 falta' : "#{absences} faltas"
  end

  def discipline_frequency
    @discipline_frequency ||= begin
      start_at = steps.map(&:start_at).compact.min
      end_at = [steps.map(&:end_at).compact.max, Date.current].compact.min
      result = {}
      if start_at.present? && end_at.present? && end_at >= start_at
        relation = DailyFrequencyStudent
                   .joins(:daily_frequency)
                   .where(student_id: student.id, active: true)
                   .where(daily_frequencies: { classroom_id: classroom.id, frequency_date: start_at..end_at })
                   .where.not(daily_frequencies: { discipline_id: nil })
        if GeneralConfiguration.current.do_not_send_justified_absence
          relation = relation.by_not_justified
        end

        relation.group('daily_frequencies.discipline_id').pluck(
          'daily_frequencies.discipline_id',
          Arel.sql("SUM(CASE WHEN COALESCE(daily_frequency_students.present, 'f') = 't' THEN 1 ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN COALESCE(daily_frequency_students.present, 'f') = 'f' THEN 1 ELSE 0 END)")
        ).each do |discipline_id, presences, absences|
          total = presences.to_i + absences.to_i
          exact = total.positive? ? (presences.to_f / total) * 100 : nil
          result[discipline_id.to_i] = {
            percentage: exact&.round,
            percentage_exact: exact,
            absences: absences.to_i,
            total: total
          }
        end
      end
      result
    end
  end

  def step_absence_message(step)
    total = absence_count(step.start_at, step.end_at)
    return 'Nenhuma falta neste período.' if total.zero?

    "Faltas neste período: #{total} #{total == 1 ? 'dia' : 'dias'}."
  end

  def format_number(value)
    number_to_rounded(value.to_d, precision: 1, strip_insignificant_zeros: false, separator: ',', delimiter: '')
  end
end
