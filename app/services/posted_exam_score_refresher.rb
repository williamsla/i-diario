# Depois que uma avaliação já enviada é excluída, recalcula a etapa.
# Quem ainda tem média local recebe o novo valor. Quem ficou sem média
# tem a nota removida no i-Educar, para o boletim não guardar o valor antigo.
class PostedExamScoreRefresher
  POSTED_TYPES = [
    ApiPostingTypes::NUMERICAL_EXAM,
    ApiPostingTypes::SCHOOL_TERM_RECOVERY
  ].freeze

  def self.snapshot(avaliation)
    {
      'classroom_id' => avaliation.classroom_id,
      'discipline_id' => avaliation.discipline_id,
      'test_date' => avaliation.test_date.to_s,
      'student_ids' => student_ids_with_note(avaliation)
    }
  end

  def self.enqueue(snapshot)
    return if snapshot.blank? || Array(snapshot['student_ids']).empty?
    return if Entity.current.blank?

    RefreshPostedExamScoresWorker.perform_async(Entity.current.id, snapshot)
  rescue StandardError => error
    Rails.logger.error("[PostedExamScoreRefresher] não enfileirou a atualização: #{error.class}: #{error.message}")
  end

  def self.student_ids_with_note(avaliation)
    DailyNoteStudent
      .joins(:daily_note)
      .where(daily_notes: { avaliation_id: avaliation.id })
      .where.not(note: nil)
      .distinct
      .pluck(:student_id)
  end

  def initialize(snapshot)
    @snapshot = snapshot.with_indifferent_access
  end

  def call
    classroom = Classroom.find_by(id: @snapshot[:classroom_id])
    discipline = Discipline.find_by(id: @snapshot[:discipline_id])
    return if classroom.blank? || discipline.blank? || discipline.api_code.blank?

    step = StepsFetcher.new(classroom).step_by_date(@snapshot[:test_date])
    return if step.blank? || !step_posted?(step)

    configuration = IeducarApiConfiguration.current
    return if configuration.url.blank?

    scores = {}
    Array(@snapshot[:student_ids]).each do |student_id|
      student = Student.find_by(id: student_id)
      next if student.blank? || student.api_code.blank?

      average = StudentAverageCalculator.new(student).calculate(
        classroom,
        discipline,
        step,
        ieducar_fallback: false
      )

      if average.nil?
        delete_remote_score(configuration, student, classroom, discipline, step)
      else
        scores[student.api_code] = average
      end
    end

    post_scores(configuration, classroom, discipline, step, scores) if scores.any?
  end

  private

  def step_posted?(step)
    relation = IeducarApiExamPosting.where(
      status: ApiSynchronizationStatus::COMPLETED,
      post_type: POSTED_TYPES
    )

    if step.is_a?(SchoolCalendarClassroomStep)
      relation.where(school_calendar_classroom_step_id: step.id).exists?
    else
      relation.where(school_calendar_step_id: step.id).exists?
    end
  end

  def delete_remote_score(configuration, student, classroom, discipline, step)
    enrollment = StudentClassroomEnrollments.for_student(student.id, classroom.id)
                                             .find { |item| item.api_code.present? }
    return if enrollment.blank?

    IeducarApi::DeleteExamScore.new(configuration.to_api).send_delete(
      etapa: step.to_number,
      matricula_id: enrollment.api_code,
      componente_curricular_id: discipline.api_code
    )
  rescue IeducarApi::Base::ApiError => error
    Rails.logger.error(
      "[PostedExamScoreRefresher] não removeu a nota do aluno #{student.id} " \
      "na etapa #{step.to_number}: #{error.message}"
    )
  end

  def post_scores(configuration, classroom, discipline, step, scores)
    notas = {
      classroom.api_code => scores.each_with_object({}) do |(student_api_code, value), acc|
        acc[student_api_code] = { discipline.api_code => { 'nota' => value } }
      end
    }

    IeducarApi::PostExams.new(configuration.to_api).send_post(
      etapa: step.to_number,
      resource: 'notas',
      notas: notas
    )
  rescue IeducarApi::Base::ApiError => error
    Rails.logger.error(
      "[PostedExamScoreRefresher] não reenviou a etapa #{step.to_number}: #{error.message}"
    )
  end
end
