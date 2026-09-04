class SchoolCalendarClassroomsSynchronizer < BaseSynchronizer
  def synchronize!
    update_school_calendar_classrooms(
      HashDecorator.new(
        api.fetch(
          escola: unity_api_code,
          ano: year,
          classroom_steps: true
        )['escolas']
      )
    )
  rescue IeducarApi::Base::ApiError => error
    synchronization.mark_as_error!(error.message || error.class.name)
  end

  private

  attr_accessor :reversed

  def api_class
    IeducarApi::SchoolCalendars
  end

  def update_school_calendar_classrooms(school_calendars)
    school_calendars.each do |school_calendar_record|
      next unless school_calendar_record.ano_em_aberto

      unity_id = unity(school_calendar_record.escola_id).try(&:id)

      next if unity_id.blank?

      school_calendar = SchoolCalendar.find_by(
        year: school_calendar_record.ano,
        unity_id: unity_id
      )

      next if school_calendar.blank?

      school_calendar_record.etapas_de_turmas.each do |school_calendar_classroom_record|
        classroom_id = classroom(school_calendar_classroom_record.turma_id).try(&:id)

        next if classroom_id.blank?

        begin
          SchoolCalendarClassroom.find_or_initialize_by(
            classroom_id: classroom_id,
            school_calendar_id: school_calendar.id
          ).tap do |school_calendar_classroom|
            school_calendar_classroom.step_type_description = school_calendar_classroom_record.descricao
            
            school_calendar_classroom.save! if school_calendar_classroom.changed?

            @school_calendar_classroom_steps_ids = []
            school_calendar_classroom_id = school_calendar_classroom.id

            update_or_create_steps(
              school_calendar_classroom_record.etapas,
              school_calendar_classroom,
              school_calendar
            )

            destroy_removed_steps(school_calendar_classroom_id)

            update_or_create_school_term_types(school_calendar_classroom)
          end
        rescue ActiveRecord::RecordInvalid => error
          known_error_messages = [
            I18n.t('ieducar_api.error.messages.must_be_less_than_end_at')
          ]

          raise error unless known_error_messages.any? { |known_error| error.message.include?(known_error) }

          mark_with_error(error)
        end
      end
    end
  rescue ActiveRecord::RecordInvalid => error
    raise error if error.message.exclude?(I18n.t('ieducar_api.error.messages.must_not_have_conflicting_steps'))
    raise error if reversed

    # Isso e necessario para quando um calendario depender da alteracao da data da etapa de outro calendario
    school_calendars.reverse!
    @reversed = true
    retry
  end

  def update_or_create_steps(school_calendar_classroom_record_steps, school_calendar_classroom, school_calendar)
    return if school_calendar_classroom_record_steps.blank?

    if keep_existing_classroom_steps?(school_calendar_classroom_record_steps, school_calendar_classroom, school_calendar)
      @school_calendar_classroom_steps_ids = school_calendar_classroom.classroom_steps.pluck(:id)
      return
    end

    last_step_end_at = school_calendar_classroom_record_steps.map { |step| step.data_fim.to_date }.max
    end_date_for_posting_on_create = last_step_end_at + 30

    school_calendar_classroom_record_steps.each do |school_calendar_classroom_step_record|
      SchoolCalendarClassroomStep.find_or_initialize_by(
        school_calendar_classroom_id: school_calendar_classroom.id,
        step_number: school_calendar_classroom_step_record.etapa
      ).tap do |school_calendar_classroom_step|
        start_at = school_calendar_classroom_step_record.data_inicio.to_date
        end_at = school_calendar_classroom_step_record.data_fim.to_date
        school_calendar_classroom_step.start_at = start_at
        school_calendar_classroom_step.end_at = end_at

        new_record = school_calendar_classroom_step.new_record?

        if new_record
          school_calendar_classroom_step.start_date_for_posting = start_at
        end

        # Regra fixa da sincronização: todas as etapas compartilham a mesma data final de lançamento.
        school_calendar_classroom_step.end_date_for_posting = end_date_for_posting_on_create

        if school_calendar_classroom_step.start_date_for_posting < start_at ||
           school_calendar_classroom_step.start_date_for_posting > school_calendar_classroom_step.end_date_for_posting
          school_calendar_classroom_step.start_date_for_posting = start_at
        end

        start_date_for_posting = school_calendar_classroom_step.start_date_for_posting
        end_date_for_posting = school_calendar_classroom_step.end_date_for_posting

        if end_date_for_posting < end_at || end_date_for_posting <= start_date_for_posting
          school_calendar_classroom_step.end_date_for_posting = end_date_for_posting_on_create
        end

        school_calendar_classroom_step.save! if school_calendar_classroom_step.changed?

        @school_calendar_classroom_steps_ids << school_calendar_classroom_step.id
      end
    end
  end

  def keep_existing_classroom_steps?(incoming_steps, school_calendar_classroom, school_calendar)
    existing_steps = school_calendar_classroom.classroom_steps
    return false if existing_steps.blank?
    return false unless incoming_matches_school_calendar?(incoming_steps, school_calendar)
    return false if step_dates(incoming_steps) == step_dates(existing_steps)

    true
  end

  def incoming_matches_school_calendar?(incoming_steps, school_calendar)
    school_steps = school_calendar.steps
    return false if school_steps.blank?

    step_dates(incoming_steps) == step_dates(school_steps)
  end

  def step_dates(steps)
    steps.map do |step|
      number = step.respond_to?(:etapa) ? step.etapa : step.step_number
      start_date = step.respond_to?(:data_inicio) ? step.data_inicio : step.start_at
      end_date = step.respond_to?(:data_fim) ? step.data_fim : step.end_at

      [number.to_i, start_date.to_date, end_date.to_date]
    end.sort
  end

  def destroy_removed_steps(school_calendar_classroom_id)
    SchoolCalendarClassroomStep.where(school_calendar_classroom_id: school_calendar_classroom_id)
                               .where.not(id: @school_calendar_classroom_steps_ids)
                               .destroy_all
  end

  def mark_with_error(error)
    unity ||= error.record&.school_calendar&.unity
    unity = "Escola: #{unity.api_code} - #{unity.name}" if unity.present?
    classroom ||= error.record&.classroom
    classroom = "Turma: #{classroom.api_code} - #{classroom.description}" if classroom.present?
    error_message = "#{unity}, #{classroom}: #{error.message || error.class.name}"

    worker_state.add_error!(error_message)
  end

  def update_or_create_school_term_types(school_calendar_classroom)
    SchoolTermTypeUpdaterWorker.perform_in(
      1.second,
      entity_id,
      nil,
      school_calendar_classroom.id
    )
  end
end
