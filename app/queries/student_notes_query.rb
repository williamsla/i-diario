class StudentNotesQuery
  def initialize(student, discipline, classroom, step_start_at, step_end_at, student_only: false)
    @student = student
    @discipline = discipline
    @classroom = classroom
    @step_start_at = step_start_at.to_date
    @step_end_at = step_end_at.to_date
    @student_only = student_only
  end

  def daily_note_students_query(student, discipline, classroom, start_date, end_date)
    DailyNoteStudent.by_student_id(student)
                    .by_discipline_id(discipline)
                    .by_classroom_id(classroom)
                    .by_test_date_between(start_date, end_date)
                    .includes(
                      daily_note: [
                        avaliation: [
                          :recovery_diary_record,
                          :test_setting_test,
                          :discipline,
                          :school_calendar
                        ]
                      ]
                    ).where.not(note: nil)
  end

  def daily_note_students
    # Inclui nota lançada mesmo se o aluno chegou no meio ou depois da etapa.
    batched_daily_note_students[student.id] || []
  end

  def previous_enrollments_daily_note_students
    daily_notes = []

    previous_enrollments.each do |enrollment|
      daily_notes.concat(
        daily_note_students_query(
          student,
          discipline,
          classroom,
          start_at(enrollment),
          end_at(enrollment)
        ).where(
          transfer_note_id: nil
        )
      )
    end

    daily_notes
  end

  def recovery_diary_records
    batched_recovery_diary_records[student.id] || []
  end

  def transfer_notes
    batched_transfer_notes[student.id] || []
  end

  def recovery_lowest_note_in_step(step)
    batched_recovery_lowest_notes(step)[student.id]
  end

  private

  attr_accessor :student, :discipline, :classroom, :step_start_at, :step_end_at
  attr_reader :student_only

  def notes_cache_key(name, extra = nil)
    key = [name, discipline.id, classroom.id]
    key << student.id if student_only
    key << extra if extra
    key
  end

  def restrict_to_student(relation)
    return relation unless student_only

    relation.where(student_id: student.id)
  end

  def batched_daily_note_students
    ReportQueryCache.fetch(notes_cache_key(:daily_note_students, [step_start_at, step_end_at])) do
      restrict_to_student(
        DailyNoteStudent.by_discipline_id(discipline)
                      .by_classroom_id(classroom)
                      .by_test_date_between(step_start_at, step_end_at)
                      .includes(
                        daily_note: [
                          avaliation: [
                            :recovery_diary_record,
                            :test_setting_test,
                            :discipline,
                            :school_calendar
                          ]
                        ]
                      )
                      .where.not(note: nil)
                      .where(transfer_note: nil)
      ).group_by(&:student_id)
    end
  end

  def batched_transfer_notes
    ReportQueryCache.fetch(notes_cache_key(:transfer_notes, [step_start_at, step_end_at])) do
      restrict_to_student(
        DailyNoteStudent.by_discipline_id(discipline)
                      .by_classroom_id(classroom)
                      .joins(:transfer_note)
                      .merge(
                        TransferNote.by_transfer_date_between(
                          step_start_at,
                          step_end_at
                        )
                      )
                      .where.not(transfer_note: nil)
      ).group_by(&:student_id)
    end
  end

  def batched_recovery_diary_records
    ReportQueryCache.fetch(notes_cache_key(:recovery_diary_records, [step_start_at, step_end_at])) do
      records = RecoveryDiaryRecord.by_discipline_id(discipline)
                                   .by_classroom_id(classroom)
                                   .joins(:students, avaliation_recovery_diary_record: [:avaliation])
                                   .merge(
                                     AvaliationRecoveryDiaryRecord.by_test_date_between(
                                       step_start_at, step_end_at
                                     )
                                   )
                                   .where.not(recovery_diary_record_students: { score: nil })
      records = records.where(recovery_diary_record_students: { student_id: student.id }) if student_only
      records = records.includes(:students, avaliation_recovery_diary_record: :avaliation)
                       .distinct
                       .to_a

      grouped = Hash.new { |hash, key| hash[key] = [] }
      records.each do |record|
        record.students.each do |recovery_student|
          next if recovery_student.score.nil?

          grouped[recovery_student.student_id] << record
        end
      end
      grouped
    end
  end

  def batched_recovery_lowest_notes(step)
    ReportQueryCache.fetch(notes_cache_key(:recovery_lowest_notes, step.id)) do
      relation = RecoveryDiaryRecordStudent
        .joins(:recovery_diary_record)
        .merge(
          RecoveryDiaryRecord.by_discipline_id(discipline)
                             .by_classroom_id(classroom)
                             .joins(:students, :avaliation_recovery_lowest_note)
                             .merge(
                               AvaliationRecoveryLowestNote.by_step_id(classroom, step.id)
                             )
        )
      relation = relation.where(recovery_diary_record_students: { student_id: student.id }) if student_only
      relation.includes(:recovery_diary_record).index_by(&:student_id)
    end
  end

  def start_at(student_enrollment_classroom)
    joined_at = student_enrollment_classroom.try(:joined_at)

    return step_start_at if joined_at.blank? || Date.parse(joined_at) < step_start_at

    Date.parse(joined_at)
  end

  def end_at(student_enrollment_classroom)
    left_at = student_enrollment_classroom.try(:left_at)

    return step_end_at if left_at.blank? || Date.parse(left_at) > step_end_at

    Date.parse(left_at)
  end

  def student_enrollment_classroom_fetcher
    @student_enrollment_classroom_fetcher ||= StudentEnrollmentClassroomFetcher.new(
      student, classroom, step_start_at, step_end_at
    )
  end

  def student_enrollment_classroom
    @student_enrollment_classroom ||= student_enrollment_classroom_fetcher.current_enrollment
  end

  def previous_enrollments
    @previous_enrollments ||= student_enrollment_classroom_fetcher.previous_enrollments
  end
end
