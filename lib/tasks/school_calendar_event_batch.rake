namespace :school_calendar_event_batch do
  desc 'Marca eventos em lote travados há muitas horas como erro'
  task mark_stuck_as_error: :environment do
    # Define o tempo mínimo em horas (padrão: 1 hora)
    # Pode ser configurado via variável de ambiente: HOURS=2 rake school_calendar_event_batch:mark_stuck_as_error
    # rake school_calendar_event_batch:mark_stuck_as_error
    hours = ENV['HOURS']&.to_i || 1
    
    puts "Buscando eventos em lote 'Em andamento' há mais de #{hours} hora(s)..."
    
    Entity.active.each do |entity|
      entity.using_connection do
        stuck_batches = SchoolCalendarEventBatch
          .where(batch_status: BatchStatus::STARTED)
          .where('created_at < ?', hours.hours.ago)
        
        count = stuck_batches.count
        
        if count > 0
          puts "  Entidade #{entity.name}: Encontrados #{count} evento(s) travado(s)"
          
          stuck_batches.find_each do |batch|
            batch.mark_with_error!(
              "Processo parado pelo sistema pois estava travado há mais de #{hours} hora(s). " \
              "Criado em: #{I18n.l(batch.created_at, format: :long)}"
            )
            puts "    - Evento '#{batch.description}' (ID: #{batch.id}) marcado como erro"
          end
        else
          puts "  Entidade #{entity.name}: Nenhum evento travado encontrado"
        end
      end
    end
    
    puts "Processo finalizado!"
  end
end

