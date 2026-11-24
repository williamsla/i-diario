class PendingRecordsAvaliationsSummary
  # not_started: sem avaliação na etapa, ou avaliação cadastrada com todas as notas em branco
  # partial: já existe nota lançada e ainda há aluno sem nota
  # complete: todos os alunos da etapa estão com nota
  NOT_STARTED = 'not_started'
  PARTIAL = 'partial'
  COMPLETE = 'complete'

  def initialize(classroom:, start_date:, end_date:, pending_records:)
    @classroom = classroom
    @start_date = start_date
    @end_date = end_date
    @pending_records = pending_records
  end

  def apply!
    optional_ids = optional_discipline_ids
    show_message = GeneralConfiguration.show_optional_discipline_note_message?

    @pending_records.each do |record|
      record[:notes_required] = !optional_ids.include?(record[:discipline_id])
    end

    countable_ids = @pending_records.select { |record| count_notes?(record, show_message) }
                                    .map { |record| record[:discipline_id] }
                                    .uniq
    return @pending_records if countable_ids.blank?

    students_without_note_by_discipline = count_students_without_note_by_discipline(countable_ids)
    created_avaliations_by_discipline = count_created_avaliations_by_discipline(countable_ids)
    launched_note_discipline_ids = discipline_ids_with_launched_note(created_avaliations_by_discipline.keys)
    classroom_students_count = count_classroom_students

    @pending_records.each do |record|
      next unless count_notes?(record, show_message)

      discipline_id = record[:discipline_id]
      created_count = created_avaliations_by_discipline[discipline_id] || 0
      launched = launched_note_discipline_ids.include?(discipline_id.to_i)

      if created_count.zero?
        record[:students_without_note_count] = classroom_students_count
        record[:students_without_note_from_classroom_total] = true
      else
        record[:students_without_note_count] = students_without_note_by_discipline[discipline_id] || 0
        record[:students_without_note_from_classroom_total] = false
      end

      record[:students_without_note_status] = note_status(
        created_count,
        record[:students_without_note_count],
        launched
      )
    end

    @pending_records
  end

  private

  def note_status(created_count, without_note_count, launched)
    return NOT_STARTED if created_count.zero? || !launched
    return PARTIAL if without_note_count.to_i.positive?

    COMPLETE
  end

  # Componente com "Desconsiderar o componente na aprovação/reprovação dos alunos?"
  # no i-Educar não entra na aprovação. O ícone do dashboard é opcional: com o
  # aviso desligado, a célula confere o lançamento como nas demais disciplinas.
  def count_notes?(record, show_message)
    return false if record[:discipline_id].blank?
    return true if record[:notes_required]

    !show_message
  end

  def optional_discipline_ids
    ids = @pending_records.map { |record| record[:discipline_id] }.compact.uniq
    return Set.new if ids.blank?

    Discipline.where(id: ids, disregard_for_progression: true).pluck(:id).to_set
  end

  def count_students_without_note_by_discipline(discipline_ids)
    DailyNoteStudent
      .active
      .where(note: nil, transfer_note_id: nil)
      .joins(daily_note: [:avaliation, :daily_note_status])
      .merge(DailyNote.by_classroom_id(@classroom.id))
      .merge(Avaliation.by_discipline_id(discipline_ids))
      .merge(Avaliation.by_test_date_between(@start_date, @end_date))
      .merge(DailyNoteStatus.by_status(DailyNoteStatuses::INCOMPLETE))
      .group('avaliations.discipline_id')
      .count('DISTINCT daily_note_students.student_id')
  end

  # Nota preenchida ou nota de transferência: o lançamento da etapa já começou.
  def discipline_ids_with_launched_note(discipline_ids)
    return Set.new if discipline_ids.blank?

    DailyNoteStudent
      .active
      .where('daily_note_students.note IS NOT NULL OR daily_note_students.transfer_note_id IS NOT NULL')
      .joins(daily_note: :avaliation)
      .merge(DailyNote.by_classroom_id(@classroom.id))
      .merge(Avaliation.by_discipline_id(discipline_ids))
      .merge(Avaliation.by_test_date_between(@start_date, @end_date))
      .distinct
      .pluck('avaliations.discipline_id')
      .map(&:to_i)
      .to_set
  end

  def count_created_avaliations_by_discipline(discipline_ids)
    Avaliation
      .by_classroom_id(@classroom.id)
      .by_discipline_id(discipline_ids)
      .by_test_date_between(@start_date, @end_date)
      .group(:discipline_id)
      .count
  end

  def count_classroom_students
    enrollments = StudentEnrollmentsList.new(
      classroom: @classroom.id,
      discipline: nil,
      start_at: @start_date,
      end_at: @end_date,
      score_type: StudentEnrollmentScoreTypeFilters::NUMERIC,
      search_type: :by_date_range,
      show_inactive: false
    ).student_enrollments

    enrollments.map(&:student_id).uniq.count
  end
end
