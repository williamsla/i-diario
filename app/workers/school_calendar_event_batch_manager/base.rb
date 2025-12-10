module SchoolCalendarEventBatchManager
  class Base
    include Sidekiq::Worker

    sidekiq_options unique: :until_and_while_executing, queue: :low, retry: 3, dead: false

    sidekiq_retries_exhausted do |msg, exception|
      entity_id, school_calendar_event_batch_id, user_id, action_name = msg['args']
      
      Entity.find(entity_id).using_connection do
        begin
          batch = SchoolCalendarEventBatch.find(school_calendar_event_batch_id)
          batch.mark_with_error!("Erro após 3 tentativas: #{exception.message}")
        rescue StandardError => e
          Rails.logger.error("Erro ao marcar evento em lote como erro após retries esgotados: #{e.message}")
        end
      end
    end

    protected

    def notify(source, message, user_id)
      SystemNotificationCreator.create!(
        source: source,
        title: I18n.t('navigation.school_calendar_event_batches'),
        description: message,
        users: [User.find(user_id)]
      )
    end
  end
end
