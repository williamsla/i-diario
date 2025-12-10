module SchoolCalendarEventBatchManager
  class EventCreatorWorker < Base
    class EventsNotCreatedError < StandardError; end

    def perform(entity_id, school_calendar_event_batch_id, user_id, action_name)
      Rails.logger.info("Iniciando processamento de evento em lote #{school_calendar_event_batch_id} para entity #{entity_id}")
      
      entity = Entity.find_by(id: entity_id)
      unless entity
        error_message = "Entity com id #{entity_id} não encontrada"
        Rails.logger.error(error_message)
        mark_batch_with_error(school_calendar_event_batch_id, error_message)
        return
      end
      
      entity.using_connection do
        school_calendar_event_batch = nil
        begin
          school_calendar_event_batch = SchoolCalendarEventBatch.find(school_calendar_event_batch_id)
          created = false
          
          school_calendars = SchoolCalendar.by_year(school_calendar_event_batch.year)
          Rails.logger.info("Encontrados #{school_calendars.count} calendário(s) escolar(es) para o ano #{school_calendar_event_batch.year}")

          school_calendars.each do |school_calendar|
            begin
              SchoolCalendarEvent.find_or_initialize_by(
                school_calendar_id: school_calendar.id,
                batch_id: school_calendar_event_batch.id
              ).tap do |event|
                event.description = school_calendar_event_batch.description
                event.start_date = school_calendar_event_batch.start_date
                event.end_date = school_calendar_event_batch.end_date
                event.event_type = school_calendar_event_batch.event_type
                event.periods = school_calendar_event_batch.periods
                event.legend = school_calendar_event_batch.legend
                event.show_in_frequency_record = school_calendar_event_batch.show_in_frequency_record
                event.save! if event.changed?

                created = true

                school_calendars_days(school_calendar_event_batch, action_name)
              end
            rescue ActiveRecord::RecordInvalid
              unity_name = Unity.find_by(id: school_calendar.unity_id)&.name

              school_calendar.steps.each do |step|
                if school_calendar_event_batch.start_date.between?(step.start_at, step.end_at) &&
                   school_calendar_event_batch.end_date.between?(step.start_at, step.end_at)

                  notify(
                    school_calendar_event_batch,
                    "A criação do evento #{school_calendar_event_batch.description} não foi efetuada para a escola\
                    #{unity_name} pois a mesma já possui um evento na data #{school_calendar_event_batch.start_date.strftime('%d/%m/%Y')}.",
                    user_id
                  )
                else
                  notify(
                    school_calendar_event_batch,
                    "A criação do evento #{school_calendar_event_batch.description} não foi efetuada para a escola\
                    #{unity_name} pois a data #{school_calendar_event_batch.start_date.strftime('%d/%m/%Y')} não está dentro do período letivo.",
                    user_id
                  )
                end
              end
              next
            end
          end

          if !created
            error_message = "Nenhum evento foi criado. Verifique se existem calendários escolares para o ano #{school_calendar_event_batch.year}."
            Rails.logger.error(error_message)
            raise EventsNotCreatedError, error_message
          end

          school_calendar_event_batch.update(batch_status: BatchStatus::COMPLETED)
          Rails.logger.info("Evento em lote #{school_calendar_event_batch_id} finalizado com sucesso")
          notify(
            school_calendar_event_batch,
            "A criação do evento em lote #{school_calendar_event_batch.description} foi finalizada.",
            user_id
          )
        rescue StandardError => error
          Rails.logger.error("Erro ao processar evento em lote #{school_calendar_event_batch_id}: #{error.class} - #{error.message}")
          Rails.logger.error(error.backtrace.join("\n")) if error.backtrace
          
          mark_batch_with_error(school_calendar_event_batch_id, error.message, school_calendar_event_batch)
        end
      end
    end

    def school_calendars_days(school_calendar_event_batch, action_name)
      school_calendars = school_calendars(school_calendar_event_batch)
      events = school_calendar_event_batch.school_calendar_events
      start_date = school_calendar_event_batch.start_date
      end_date = school_calendar_event_batch.end_date

      SchoolCalendarEventDays.update_school_days(
        school_calendars,
        events,
        action_name,
        start_date,
        end_date
      )
    end

    def school_calendars(school_calendar_event_batch)
      SchoolCalendar.by_year(school_calendar_event_batch.year)
    end

    private

    def mark_batch_with_error(school_calendar_event_batch_id, error_message, batch = nil)
      if batch.present?
        batch.mark_with_error!(error_message)
      else
        # Tenta encontrar o batch em qualquer conexão disponível
        begin
          # Tenta na conexão padrão primeiro
          batch = SchoolCalendarEventBatch.find(school_calendar_event_batch_id)
          batch.mark_with_error!(error_message)
        rescue StandardError => find_error
          # Se falhar, tenta encontrar a entidade e usar sua conexão
          begin
            # Busca todas as entidades ativas e tenta encontrar o batch
            Entity.active.each do |entity|
              entity.using_connection do
                batch = SchoolCalendarEventBatch.find_by(id: school_calendar_event_batch_id)
                if batch
                  batch.mark_with_error!(error_message)
                  break
                end
              end
            rescue StandardError => e
              Rails.logger.debug("Erro ao buscar batch na entity #{entity.id}: #{e.message}")
              next
            end
          rescue StandardError => e
            Rails.logger.error("Erro ao marcar batch #{school_calendar_event_batch_id} como erro: #{e.message}")
          end
        end
      end
    end
  end
end
