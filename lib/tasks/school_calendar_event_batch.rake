namespace :school_calendar_event_batch do
  desc 'Marca eventos em lote travados há muitas horas como erro'
  task mark_stuck_as_error: :environment do
    # Define o tempo mínimo em horas (padrão: 1 hora)
    # Pode ser configurado via variável de ambiente: HOURS=2 rake school_calendar_event_batch:mark_stuck_as_error
    # RAILS_ENV=production rake school_calendar_event_batch:mark_stuck_as_error
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

  desc 'Reprocessa eventos em lote travados (executa o worker manualmente)'
  task reprocess_stuck: :environment do
    hours = ENV['HOURS']&.to_i || 1
    
    puts "Buscando eventos em lote 'Em andamento' há mais de #{hours} hora(s) para reprocessar..."
    
    Entity.active.each do |entity|
      entity.using_connection do
        stuck_batches = SchoolCalendarEventBatch
          .where(batch_status: BatchStatus::STARTED)
          .where('created_at < ?', hours.hours.ago)
        
        count = stuck_batches.count
        
        if count > 0
          puts "  Entidade #{entity.name}: Encontrados #{count} evento(s) travado(s)"
          
          stuck_batches.find_each do |batch|
            puts "    - Reprocessando evento '#{batch.description}' (ID: #{batch.id})..."
            
            begin
              # Busca o usuário admin (ou usa o primeiro usuário disponível)
              admin_role = Role.order(:id).find_by(access_level: 'administrator')
              user = if admin_role
                User.joins(:user_roles).where(user_roles: { role_id: admin_role.id }).first
              else
                User.find_by(login: 'admin')
              end
              user ||= User.first
              
              if user.nil?
                puts "      ERRO: Nenhum usuário encontrado para processar o evento"
                batch.mark_with_error!("Nenhum usuário disponível para processar o evento")
                next
              end
              
              # Executa o worker de forma síncrona
              SchoolCalendarEventBatchManager::EventCreatorWorker.new.perform(
                entity.id,
                batch.id,
                user.id,
                'create'
              )
              
              # Verifica o status após processamento
              batch.reload
              if batch.completed?
                puts "      ✓ Evento processado com sucesso!"
              elsif batch.error?
                puts "      ✗ Evento marcado como erro: #{batch.error_message}"
              else
                puts "      ? Evento ainda em andamento após processamento"
              end
            rescue StandardError => e
              puts "      ERRO ao processar: #{e.message}"
              batch.mark_with_error!("Erro ao reprocessar: #{e.message}")
            end
          end
        else
          puts "  Entidade #{entity.name}: Nenhum evento travado encontrado"
        end
      end
    end
    
    puts "Processo finalizado!"
  end
end

