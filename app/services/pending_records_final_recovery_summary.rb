# frozen_string_literal: true

# Pendência de recuperação final no dashboard de datas pendentes.
#
# Quem está em exame vem do iEducar e pode ser cacheado (~5 min): muda quando
# as médias do ano são enviadas. A nota lançada no i-Diário NÃO é cacheada —
# o professor precisa ver a pílula atualizar na hora após salvar o diário,
# inclusive se deixar um aluno sem nota.
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

  def payload
    {
      counts: counts.transform_keys(&:to_s),
      errors: errors.transform_keys(&:to_s)
    }
  end

  private

  def calculate
    @counts = {}
    @errors = {}
    return if @discipline_ids.blank? || @classroom.blank? || @school_calendar.blank?

    scored_ids_by_discipline = scored_student_ids_by_discipline

    @discipline_ids.each do |discipline_id|
      eligible_ids = eligible_student_ids(discipline_id)

      if eligible_ids.nil?
        @errors[discipline_id] = true
        next
      end

      scored_ids = scored_ids_by_discipline[discipline_id] || Set.new
      @counts[discipline_id] = (eligible_ids - scored_ids).size
    end
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
