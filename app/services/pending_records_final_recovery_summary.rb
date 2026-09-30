# frozen_string_literal: true

# Pendência de recuperação final no dashboard de datas pendentes.
#
# Quem está em exame vem do iEducar e pode ser cacheado (~5 min): muda quando
# as médias do ano são enviadas. A nota lançada no i-Diário NÃO é cacheada —
# o professor precisa ver a pílula atualizar na hora após salvar o diário,
# inclusive se deixar um aluno sem nota.
#
# Enquanto alguma etapa da disciplina ainda não tiver as notas cadastradas,
# a recuperação final não aparece como concluída: fica pendente até todas
# as etapas terem avaliação com nota.
class PendingRecordsFinalRecoverySummary
  ELIGIBLE_CACHE_TTL = 5.minutes
  NUMERIC_SCORE_TYPES = [ScoreTypes::NUMERIC, ScoreTypes::NUMERIC_AND_CONCEPT].freeze

  def self.available_for?(classroom)
    return false if classroom.blank?

    classroom.classrooms_grades.includes(exam_rule: :differentiated_exam_rule).any? do |classrooms_grade|
      rules = [classrooms_grade.exam_rule, classrooms_grade.exam_rule&.differentiated_exam_rule].compact
      rules.any? { |rule| uses_final_recovery?(rule) }
    end
  end

  def self.uses_final_recovery?(exam_rule)
    return false if exam_rule.blank?

    NUMERIC_SCORE_TYPES.include?(exam_rule.score_type) &&
      exam_rule.final_recovery_maximum_score.to_i.positive?
  end

  def self.expire!(classroom_id: nil)
    if classroom_id.present?
      Rails.cache.write(classroom_version_key(classroom_id), Time.current.to_i, expires_in: 1.day)
    else
      Rails.cache.write(global_version_key, Time.current.to_i, expires_in: 1.day)
    end
  end

  def self.expire_for_posting!(_posting = nil)
    expire!
  end

  def self.classroom_version_key(classroom_id)
    ['final-recovery-eligible-version', Entity.current&.id, classroom_id]
  end

  def self.global_version_key
    ['final-recovery-eligible-version', Entity.current&.id, 'global']
  end

  def initialize(classroom:, school_calendar:, discipline_ids:, api_configuration: IeducarApiConfiguration.current)
    @classroom = classroom
    @school_calendar = school_calendar
    @discipline_ids = Array(discipline_ids).map(&:to_i).reject(&:zero?).uniq
    @api_configuration = api_configuration
  end

  def counts
    calculate unless defined?(@counts)
    @counts
  end

  def errors
    calculate unless defined?(@errors)
    @errors
  end

  def waiting_step_notes
    calculate unless defined?(@waiting_step_notes)
    @waiting_step_notes
  end

  def payload
    {
      counts: counts.transform_keys(&:to_s),
      errors: errors.transform_keys(&:to_s),
      waiting_step_notes: waiting_step_notes.transform_keys(&:to_s)
    }
  end

  private

  def calculate
    @counts = {}
    @errors = {}
    @waiting_step_notes = {}
    return if @discipline_ids.blank? || @classroom.blank? || @school_calendar.blank?

    waiting_ids = discipline_ids_waiting_for_step_notes
    waiting_ids.each { |discipline_id| @waiting_step_notes[discipline_id] = true }

    pending_ids = @discipline_ids - waiting_ids
    return if pending_ids.blank?

    scored_ids_by_discipline = scored_student_ids_by_discipline

    pending_ids.each do |discipline_id|
      eligible_ids = eligible_student_ids(discipline_id)

      if eligible_ids.nil?
        @errors[discipline_id] = true
        next
      end

      scored_ids = scored_ids_by_discipline[discipline_id] || Set.new
      @counts[discipline_id] = (eligible_ids - scored_ids).size
    end
  end

  def discipline_ids_waiting_for_step_notes
    steps = StepsFetcher.new(@classroom).steps.to_a
    return [] if steps.blank?

    year_start = steps.map(&:start_at).min
    year_end = steps.map(&:end_at).max
    avaliation_dates = dates_by_discipline(avaliation_dates_for(year_start, year_end))
    incomplete_dates = dates_by_discipline(incomplete_note_dates_for(year_start, year_end))

    @discipline_ids.select do |discipline_id|
      steps_missing_notes?(steps, avaliation_dates[discipline_id], incomplete_dates[discipline_id])
    end
  end

  def avaliation_dates_for(year_start, year_end)
    Avaliation
      .by_classroom_id(@classroom.id)
      .by_discipline_id(@discipline_ids)
      .by_test_date_between(year_start, year_end)
      .pluck(:discipline_id, :test_date)
  end

  def incomplete_note_dates_for(year_start, year_end)
    DailyNoteStudent
      .active
      .where(note: nil, transfer_note_id: nil)
      .joins(daily_note: [:avaliation, :daily_note_status])
      .merge(DailyNote.by_classroom_id(@classroom.id))
      .merge(Avaliation.by_discipline_id(@discipline_ids))
      .merge(Avaliation.by_test_date_between(year_start, year_end))
      .merge(DailyNoteStatus.by_status(DailyNoteStatuses::INCOMPLETE))
      .pluck('avaliations.discipline_id', 'avaliations.test_date')
  end

  def dates_by_discipline(rows)
    rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(discipline_id, test_date), hash|
      hash[discipline_id] << test_date
    end
  end

  def steps_missing_notes?(steps, avaliation_dates, incomplete_dates)
    steps.any? do |step|
      next true if Array(avaliation_dates).none? { |date| date_in_step?(date, step) }

      Array(incomplete_dates).any? { |date| date_in_step?(date, step) }
    end
  end

  def date_in_step?(date, step)
    day = date.to_date
    day >= step.start_at.to_date && day <= step.end_at.to_date
  end

  def eligible_student_ids(discipline_id)
    cached = Rails.cache.read(eligible_cache_key(discipline_id))
    return Array(cached).to_set if cached

    ids = StudentsInFinalRecoveryFetcher.new(@api_configuration)
                                        .fetch(@classroom.id, discipline_id)
                                        .map(&:id)

    Rails.cache.write(eligible_cache_key(discipline_id), ids, expires_in: ELIGIBLE_CACHE_TTL)
    ids.to_set
  rescue StandardError => error
    Honeybadger.notify(error)
    nil
  end

  def scored_student_ids_by_discipline
    RecoveryDiaryRecordStudent
      .joins(recovery_diary_record: :final_recovery_diary_record)
      .where(recovery_diary_records: { classroom_id: @classroom.id, discipline_id: @discipline_ids })
      .where(final_recovery_diary_records: { school_calendar_id: @school_calendar.id })
      .where.not(score: nil)
      .pluck('recovery_diary_records.discipline_id', :student_id)
      .each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |(discipline_id, student_id), hash|
        hash[discipline_id] << student_id
      end
  end

  def eligible_cache_key(discipline_id)
    [
      'final-recovery-eligible-ids',
      Entity.current&.id,
      @classroom.id,
      discipline_id,
      Rails.cache.read(self.class.classroom_version_key(@classroom.id)).to_i,
      Rails.cache.read(self.class.global_version_key).to_i
    ]
  end
end
