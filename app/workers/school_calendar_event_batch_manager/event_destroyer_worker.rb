module SchoolCalendarEventBatchManager
  class EventDestroyerWorker < Base
    class EventsNotDestroyedError < StandardError; end

    EVENT_NOT_DESTROYED = 'Não foi possível excluir o evento'.freeze

    def perform(entity_id, school_calendar_event_batch_id, user_id, action_name)
      Rails.logger.info("=== INÍCIO: Excluindo evento em lote #{school_calendar_event_batch_id} para entity #{entity_id} ===")
      
      begin
        entity = Entity.find(entity_id)
        Rails.logger.info("Entity encontrada: #{entity.name} (id: #{entity.id})")
      rescue ActiveRecord::RecordNotFound => e
        error_message = "Entity com id #{entity_id} não encontrada"
        Rails.logger.error(error_message)
        mark_batch_with_error_simple(school_calendar_event_batch_id, error_message)
        return
      end
      
      entity.using_connection do
        Rails.logger.info("Conexão com entity estabelecida")
        school_calendar_event_batch = nil
        begin
          school_calendar_event_batch = SchoolCalendarEventBatch.find(school_calendar_event_batch_id)
          events = SchoolCalendarEvent.where(batch_id: school_calendar_event_batch.id)
          
          Rails.logger.info("Encontrados #{events.count} evento(s) para excluir")

          if events.blank?
            school_calendar_event_batch.destroy!
            Rails.logger.info("Batch excluído com sucesso (sem eventos associados)")
            return
          end

          destroyed = false

          events.each do |event|
            begin
              school_calendars_days(school_calendar_event_batch, action_name)
              event.destroy!
              destroyed = true
              Rails.logger.info("Evento #{event.id} excluído com sucesso")
            rescue ActiveRecord::RecordNotDestroyed => e
              school_calendar = event.school_calendar
              unity_name = Unity.find_by(id: school_calendar.unity_id)&.name
              Rails.logger.warn("Não foi possível excluir evento #{event.id} em #{unity_name}: #{e.message}")
              notify(
                school_calendar_event_batch,
                "#{EVENT_NOT_DESTROYED}: #{school_calendar_event_batch.description} em #{unity_name}",
                user_id
              )
              next
            end
          end

          if !destroyed
            error_message = "Nenhum evento foi excluído"
            Rails.logger.error(error_message)
            raise EventsNotDestroyedError, error_message
          end

          school_calendar_event_batch.destroy!
          Rails.logger.info("=== FIM: Evento em lote #{school_calendar_event_batch_id} excluído com sucesso ===")
        rescue StandardError => error
          Rails.logger.error("Erro ao excluir evento em lote #{school_calendar_event_batch_id}: #{error.class} - #{error.message}")
          Rails.logger.error(error.backtrace.join("\n")) if error.backtrace
          mark_batch_with_error_simple(school_calendar_event_batch_id, error.message, school_calendar_event_batch)
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
      school_calendars_ids = school_calendar_event_batch.school_calendar_events.map(&:school_calendar_id)

      SchoolCalendar.includes(:events).find(school_calendars_ids)
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
