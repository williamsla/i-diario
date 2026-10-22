class PendingRecordsAvaliationsSummary
  def initialize(classroom:, start_date:, end_date:, pending_records:)
    @classroom = classroom
    @start_date = start_date
    @end_date = end_date
    @pending_records = pending_records
  end

  def apply!
    optional_ids = optional_discipline_ids

    @pending_records.each do |record|
      record[:notes_required] = !optional_ids.include?(record[:discipline_id])
    end

    required_ids = @pending_records.select { |record| record[:notes_required] && record[:discipline_id].present? }
                                   .map { |record| record[:discipline_id] }
                                   .uniq
    return @pending_records if required_ids.blank?

    students_without_note_by_discipline = count_students_without_note_by_discipline(required_ids)
    created_avaliations_by_discipline = count_created_avaliations_by_discipline(required_ids)
    classroom_students_count = count_classroom_students

    @pending_records.each do |record|
      next unless record[:notes_required] && record[:discipline_id].present?

      discipline_id = record[:discipline_id]
      created_count = created_avaliations_by_discipline[discipline_id] || 0

      if created_count.zero?
        record[:students_without_note_count] = classroom_students_count
        record[:students_without_note_from_classroom_total] = true
      else
        record[:students_without_note_count] = students_without_note_by_discipline[discipline_id] || 0
        record[:students_without_note_from_classroom_total] = false
      end
    end

    @pending_records
  end

  private

  # Componente com "Desconsiderar o componente na aprovação/reprovação dos alunos?"
  # no i-Educar não gera pendência de nota numérica nem de recuperação final.
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
