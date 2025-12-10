module SchoolCalendarEventBatchManager
  class EventCreatorWorker < Base
    class EventsNotCreatedError < StandardError; end

    def perform(entity_id, school_calendar_event_batch_id, user_id, action_name)
      Rails.logger.info("=== INÍCIO: Processando evento em lote #{school_calendar_event_batch_id} para entity #{entity_id} ===")
      
      # Tenta usar Entity.current primeiro (definido pelo controller), senão busca por ID
      entity = Entity.current || begin
        Entity.find(entity_id)
      rescue ActiveRecord::RecordNotFound => e
        error_message = "Entity com id #{entity_id} não encontrada"
        Rails.logger.error(error_message)
        mark_batch_with_error_simple(school_calendar_event_batch_id, error_message)
        return
      end
      
      Rails.logger.info("Entity encontrada: #{entity.name} (id: #{entity.id})")
      
      entity.using_connection do
        Rails.logger.info("Conexão com entity estabelecida")
        school_calendar_event_batch = nil
        begin
          school_calendar_event_batch = SchoolCalendarEventBatch.find(school_calendar_event_batch_id)
          created = false
          
          school_calendars = SchoolCalendar.by_year(school_calendar_event_batch.year)
          Rails.logger.info("Encontrados #{school_calendars.count} calendário(s) escolar(es) para o ano #{school_calendar_event_batch.year}")

          events_created_count = 0
          events_failed_count = 0
          validation_errors = []

          school_calendars.each do |school_calendar|
            begin
              event = SchoolCalendarEvent.find_or_initialize_by(
                school_calendar_id: school_calendar.id,
                batch_id: school_calendar_event_batch.id
              )
              
              event.description = school_calendar_event_batch.description
              event.start_date = school_calendar_event_batch.start_date
              event.end_date = school_calendar_event_batch.end_date
              event.event_type = school_calendar_event_batch.event_type
              event.periods = school_calendar_event_batch.periods
              event.legend = school_calendar_event_batch.legend
              event.show_in_frequency_record = school_calendar_event_batch.show_in_frequency_record
              
              if event.changed?
                event.save!
                Rails.logger.info("Evento criado/atualizado com sucesso para calendário escolar ID #{school_calendar.id} (Unity ID: #{school_calendar.unity_id})")
                events_created_count += 1
                created = true
                school_calendars_days(school_calendar_event_batch, action_name)
              else
                Rails.logger.info("Evento já existe e não foi alterado para calendário escolar ID #{school_calendar.id} (Unity ID: #{school_calendar.unity_id})")
                events_created_count += 1
                created = true
              end
            rescue ActiveRecord::RecordInvalid => e
              events_failed_count += 1
              unity_name = Unity.find_by(id: school_calendar.unity_id)&.name || "ID #{school_calendar.unity_id}"
              error_details = {
                unity: unity_name,
                calendar_id: school_calendar.id,
                errors: e.record.errors.full_messages
              }
              validation_errors << error_details
              
              Rails.logger.error("Erro de validação ao criar evento para escola #{unity_name} (Calendário ID: #{school_calendar.id}): #{e.record.errors.full_messages.join(', ')}")

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
            rescue StandardError => e
              events_failed_count += 1
              unity_name = Unity.find_by(id: school_calendar.unity_id)&.name || "ID #{school_calendar.unity_id}"
              Rails.logger.error("Erro inesperado ao criar evento para escola #{unity_name} (Calendário ID: #{school_calendar.id}): #{e.class} - #{e.message}")
              Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
              next
            end
          end

          Rails.logger.info("Resumo: #{events_created_count} evento(s) criado(s)/atualizado(s), #{events_failed_count} evento(s) falharam")

          if !created
            error_message = "Nenhum evento foi criado. Verifique se existem calendários escolares para o ano #{school_calendar_event_batch.year}."
            if validation_errors.any?
              error_details = validation_errors.map { |err| "#{err[:unity]}: #{err[:errors].join(', ')}" }.join('; ')
              error_message += " Erros de validação: #{error_details}"
            end
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
          
          mark_batch_with_error_simple(school_calendar_event_batch_id, error.message, school_calendar_event_batch)
        end
      end
      
      Rails.logger.info("=== FIM: Processamento de evento em lote #{school_calendar_event_batch_id} concluído ===")
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

    def mark_batch_with_error_simple(school_calendar_event_batch_id, error_message, batch = nil)
      Rails.logger.info("Tentando marcar batch #{school_calendar_event_batch_id} como erro: #{error_message}")
      
      if batch.present?
        begin
          batch.mark_with_error!(error_message)
          Rails.logger.info("Batch marcado como erro com sucesso (usando batch existente)")
        rescue => e
          Rails.logger.error("Erro ao marcar batch existente: #{e.message}")
        end
      else
        # Tenta encontrar o batch na conexão atual
        begin
          batch = SchoolCalendarEventBatch.find(school_calendar_event_batch_id)
          batch.mark_with_error!(error_message)
          Rails.logger.info("Batch marcado como erro com sucesso (encontrado na conexão atual)")
        rescue StandardError => find_error
          Rails.logger.error("Não foi possível encontrar ou marcar batch #{school_calendar_event_batch_id}: #{find_error.message}")
        end
      end
    end
  end
end
