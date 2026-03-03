namespace :ieducar_api do
  desc 'I-Educar API synchronization (obrigatório: DOMAIN= ou TENANT=)'
  task :synchronize, [:full_synchronization, :current_years] => :environment do |_task, args|
    args.with_defaults(
      full_synchronization: true,
      current_years: true
    )

    full_synchronization = ActiveRecord::Type::Boolean.new.cast(args.full_synchronization)
    current_years = ActiveRecord::Type::Boolean.new.cast(args.current_years)

    entities = if ENV["DOMAIN"].present?
                 entity = Entity.find_by(domain: ENV["DOMAIN"])
                 raise "Entidade não encontrada para DOMAIN=#{ENV['DOMAIN']}" unless entity
                 [entity]
               elsif ENV["TENANT"].present?
                 entity = Entity.find_by(name: ENV["TENANT"])
                 raise "Entidade não encontrada para TENANT=#{ENV['TENANT']}" unless entity
                 [entity]
               else
                 raise "Via rake é obrigatório informar DOMAIN= ou TENANT=. Ex: DOMAIN=escola.gov.br rake ieducar_api:synchronize"
               end

    entities.each do |entity|
      entity.using_connection do
        puts "Enfileirando sincronização: #{entity.name} (#{entity.domain})"
        IeducarSynchronizerWorker.perform_async(entity.id, nil, full_synchronization, current_years)
      end
    end
  end

  desc 'Cancela sincronização em andamento (obrigatório: DOMAIN= ou TENANT=)'
  task cancel_sync: :environment do
    entity = if ENV["DOMAIN"].present?
               e = Entity.find_by(domain: ENV["DOMAIN"])
               raise "Entidade não encontrada para DOMAIN=#{ENV['DOMAIN']}" unless e
               e
             elsif ENV["TENANT"].present?
               e = Entity.find_by(name: ENV["TENANT"])
               raise "Entidade não encontrada para TENANT=#{ENV['TENANT']}" unless e
               e
             else
               raise "Obrigatório informar DOMAIN= ou TENANT=. Ex: DOMAIN=escola.gov.br rake ieducar_api:cancel_sync"
             end

    entity.using_connection do
      started = IeducarApiSynchronization.started
      if started.empty?
        puts "Nenhuma sincronização em andamento para #{entity.name} (#{entity.domain})."
        next
      end
      started.each do |sync|
        sync.cancel_running!
        puts "Sincronização ##{sync.id} cancelada para #{entity.name} (#{entity.domain})."
      end
    end
  end

  desc 'Cancela envio de notas travados há 1 dia ou mais (obrigatório: DOMAIN= ou TENANT=)'
  task cancel: :environment do
    entities = if ENV["DOMAIN"].present?
                 entity = Entity.find_by(domain: ENV["DOMAIN"])
                 raise "Entidade não encontrada para DOMAIN=#{ENV['DOMAIN']}" unless entity
                 [entity]
               elsif ENV["TENANT"].present?
                 entity = Entity.find_by(name: ENV["TENANT"])
                 raise "Entidade não encontrada para TENANT=#{ENV['TENANT']}" unless entity
                 [entity]
               else
                 raise "Via rake é obrigatório informar DOMAIN= ou TENANT=. Ex: DOMAIN=escola.gov.br rake ieducar_api:cancel"
               end

    entities.each do |entity|
      entity.using_connection do
        postings = IeducarApiExamPosting.where(status: :started)
                                        .where('created_at < ?', 1.day.ago)
        puts "#{entity.name} (#{entity.domain}): cancelando #{postings.count} envios"
        postings.each do |posting|
          posting.add_error!(
            I18n.t('ieducar_api.error.messages.sync_error'),
            'Processo parado pelo sistema pois estava travado.'
          )
          posting.mark_as_error!
        end
      end
    end
  end
end
