namespace :content_records do
  def content_records_entity
    return Entity.current if Entity.current.present?

    entity = if ENV['DOMAIN'].present?
               Entity.find_by(domain: ENV['DOMAIN'])
             elsif ENV['TENANT'].present?
               Entity.find_by(name: ENV['TENANT'])
             end

    unless entity
      examples = Entity.limit(5).pluck(:name, :domain).map { |name, domain| "#{name} (#{domain})" }.join(', ')
      examples += '...' if Entity.count > 5
      raise "Entidade não encontrada. Use DOMAIN=host ou TENANT=nome_entidade. Exemplos: #{examples}"
    end

    entity
  end

  def with_content_records_entity_connection
    entity = content_records_entity

    if Entity.current.present?
      yield entity
    else
      entity.using_connection { yield entity }
    end
  end

  def parse_ka_record_ids
    raw_ids = ENV['KA_RECORD_IDS'].presence || ENV.fetch('ka_record_ids', nil)
    raise 'Informe KA_RECORD_IDS=101,102,103' if raw_ids.blank?

    raw_ids.split(',').map(&:strip).reject(&:blank?).map(&:to_i)
  end

  def parse_discipline_record_ids
    raw_ids = ENV['DCR_RECORD_IDS'].presence || ENV.fetch('dcr_record_ids', nil)
    raise 'Informe DCR_RECORD_IDS=101,102,103' if raw_ids.blank?

    raw_ids.split(',').map(&:strip).reject(&:blank?).map(&:to_i)
  end

  def parse_optional_knowledge_area_ids
    raw_ids = ENV['KNOWLEDGE_AREA_IDS'].presence || ENV['KA_IDS'].presence
    return nil if raw_ids.blank?

    raw_ids.split(',').map(&:strip).reject(&:blank?).map(&:to_i)
  end

  def truthy_env?(key, default: false)
    value = ENV[key]
    return default if value.blank?

    %w[1 true yes sim].include?(value.to_s.downcase)
  end

  def print_migration_result(result)
    puts "Criados: #{result.created} | Ignorados (já existiam): #{result.skipped}"
    result.errors.each { |error| puts "ERRO: #{error}" }
  end

  desc <<~DESC
    Migra registros de conteúdo por área de conhecimento para registro por disciplina.

    Variáveis:
      DOMAIN ou TENANT          Entidade alvo (obrigatório se não estiver em entity:run)
      KA_RECORD_IDS             IDs separados por vírgula (ex: 101,102,103)
      DISCIPLINE_ID             ID da disciplina de destino
      DRY_RUN                   1 para simular (padrão: 1)
      DELETE_OLD                1 para remover registros por área após migrar (padrão: 0)
      SKIP_KNOWLEDGE_AREA_CHECK 1 para ignorar validação de área de conhecimento (padrão: 0)
      CLASS_NUMBER              Número da aula, se a escola usa essa configuração
      VERBOSE                   1 para exibir backtrace completo no terminal

    Exemplos:
      DOMAIN=escola.gov.br KA_RECORD_IDS=101,102 DISCIPLINE_ID=456 DRY_RUN=1 \\
        bundle exec rake content_records:migrate_from_knowledge_area

      DOMAIN=escola.gov.br KA_RECORD_IDS=101,102 DISCIPLINE_ID=456 DRY_RUN=0 \\
        bundle exec rake "entity:run[content_records:migrate_from_knowledge_area]"
  DESC
  task migrate_from_knowledge_area: :environment do
    ka_record_ids = parse_ka_record_ids
    discipline_id = ENV['DISCIPLINE_ID'].presence
    raise 'Informe DISCIPLINE_ID=456' if discipline_id.blank?

    dry_run = truthy_env?('DRY_RUN', default: true)
    delete_old = truthy_env?('DELETE_OLD')
    skip_knowledge_area_check = truthy_env?('SKIP_KNOWLEDGE_AREA_CHECK')
    class_number = ENV['CLASS_NUMBER'].presence&.to_i
    verbose = truthy_env?('VERBOSE')

    with_content_records_entity_connection do |entity|
      puts "Entidade: #{entity.name} (#{entity.domain})"
      puts "Modo: #{dry_run ? 'simulação (DRY_RUN)' : 'execução'}"
      puts "KA_RECORD_IDS=#{ka_record_ids.join(',')} → DISCIPLINE_ID=#{discipline_id}"

      result = KnowledgeAreaToDisciplineContentRecordMigrator.new(
        ka_record_ids: ka_record_ids,
        discipline_id: discipline_id,
        dry_run: dry_run,
        delete_old: delete_old,
        skip_knowledge_area_check: skip_knowledge_area_check,
        class_number: class_number,
        verbose: verbose
      ).call

      print_migration_result(result)
    end
  end

  desc <<~DESC
    Migra vários registros por área para disciplinas diferentes em lote.

    Variáveis:
      DOMAIN ou TENANT  Entidade alvo
      MIGRATIONS        Pares ka_id:discipline_id separados por vírgula (ex: 101:456,102:789)
      DRY_RUN           1 para simular (padrão: 1)
      DELETE_OLD        1 para remover registros por área após migrar (padrão: 0)
      SKIP_KNOWLEDGE_AREA_CHECK 1 para ignorar validação de área (padrão: 0)
      CLASS_NUMBER      Número da aula, se necessário
      VERBOSE           1 para exibir backtrace completo no terminal

    Exemplo:
      DOMAIN=escola.gov.br MIGRATIONS=101:456,102:456,103:789 DRY_RUN=1 \\
        bundle exec rake content_records:migrate_from_knowledge_area_batch
  DESC
  task migrate_from_knowledge_area_batch: :environment do
    raw_migrations = ENV['MIGRATIONS'].presence
    raise 'Informe MIGRATIONS=101:456,102:789' if raw_migrations.blank?

    migrations = raw_migrations.split(',').map(&:strip).reject(&:blank?).map do |pair|
      ka_id, discipline_id = pair.split(':').map(&:strip)
      raise "Par inválido em MIGRATIONS: #{pair}" if ka_id.blank? || discipline_id.blank?

      [ka_id.to_i, discipline_id.to_i]
    end

    dry_run = truthy_env?('DRY_RUN', default: true)
    delete_old = truthy_env?('DELETE_OLD')
    skip_knowledge_area_check = truthy_env?('SKIP_KNOWLEDGE_AREA_CHECK')
    class_number = ENV['CLASS_NUMBER'].presence&.to_i
    verbose = truthy_env?('VERBOSE')

    total_created = 0
    total_skipped = 0
    total_errors = []

    with_content_records_entity_connection do |entity|
      puts "Entidade: #{entity.name} (#{entity.domain})"
      puts "Modo: #{dry_run ? 'simulação (DRY_RUN)' : 'execução'}"

      migrations.each do |ka_record_id, discipline_id|
        puts "\n--- KA##{ka_record_id} → DISCIPLINE_ID=#{discipline_id} ---"

        result = KnowledgeAreaToDisciplineContentRecordMigrator.new(
          ka_record_ids: [ka_record_id],
          discipline_id: discipline_id,
          dry_run: dry_run,
          delete_old: delete_old,
          skip_knowledge_area_check: skip_knowledge_area_check,
          class_number: class_number,
          verbose: verbose
        ).call

        total_created += result.created
        total_skipped += result.skipped
        total_errors.concat(result.errors)
      end

      puts "\n=== Resumo ==="
      puts "Criados: #{total_created} | Ignorados (já existiam): #{total_skipped}"
      total_errors.each { |error| puts "ERRO: #{error}" }
    end
  end

  desc <<~DESC
    Migra registros de conteúdo por disciplina para registro por área de conhecimento.

    Variáveis:
      DOMAIN ou TENANT          Entidade alvo (obrigatório se não estiver em entity:run)
      DCR_RECORD_IDS            IDs de DisciplineContentRecord separados por vírgula
      KNOWLEDGE_AREA_IDS        IDs das áreas de destino (opcional; padrão = área da disciplina)
      DRY_RUN                   1 para simular (padrão: 1)
      DELETE_OLD                1 para remover registros por disciplina após migrar (padrão: 0)
      SKIP_KNOWLEDGE_AREA_CHECK 1 para ignorar validação de área da disciplina (padrão: 0)
      VERBOSE                   1 para exibir backtrace completo no terminal

    Exemplos:
      DOMAIN=escola.gov.br DCR_RECORD_IDS=101,102 DRY_RUN=1 \\
        bundle exec rake content_records:migrate_from_discipline

      DOMAIN=escola.gov.br DCR_RECORD_IDS=101,102 KNOWLEDGE_AREA_IDS=10 DRY_RUN=0 DELETE_OLD=1 \\
        bundle exec rake "entity:run[content_records:migrate_from_discipline]"
  DESC
  task migrate_from_discipline: :environment do
    discipline_record_ids = parse_discipline_record_ids
    knowledge_area_ids = parse_optional_knowledge_area_ids
    dry_run = truthy_env?('DRY_RUN', default: true)
    delete_old = truthy_env?('DELETE_OLD')
    skip_knowledge_area_check = truthy_env?('SKIP_KNOWLEDGE_AREA_CHECK')
    verbose = truthy_env?('VERBOSE')

    with_content_records_entity_connection do |entity|
      puts "Entidade: #{entity.name} (#{entity.domain})"
      puts "Modo: #{dry_run ? 'simulação (DRY_RUN)' : 'execução'}"
      destination = knowledge_area_ids.present? ? "KNOWLEDGE_AREA_IDS=#{knowledge_area_ids.join(',')}" : 'área da disciplina'
      puts "DCR_RECORD_IDS=#{discipline_record_ids.join(',')} → #{destination}"

      result = DisciplineToKnowledgeAreaContentRecordMigrator.new(
        discipline_record_ids: discipline_record_ids,
        knowledge_area_ids: knowledge_area_ids,
        dry_run: dry_run,
        delete_old: delete_old,
        skip_knowledge_area_check: skip_knowledge_area_check,
        verbose: verbose
      ).call

      print_migration_result(result)
    end
  end

  desc <<~DESC
    Migra vários registros por disciplina para áreas diferentes em lote.

    Variáveis:
      DOMAIN ou TENANT  Entidade alvo
      MIGRATIONS        Pares dcr_id:ka_id separados por vírgula (ex: 101:10,102:10,103:20)
                        Use dcr_id:ka_id1|ka_id2 para várias áreas no mesmo registro
      DRY_RUN           1 para simular (padrão: 1)
      DELETE_OLD        1 para remover registros por disciplina após migrar (padrão: 0)
      SKIP_KNOWLEDGE_AREA_CHECK 1 para ignorar validação de área (padrão: 0)
      VERBOSE           1 para exibir backtrace completo no terminal

    Exemplo:
      DOMAIN=escola.gov.br MIGRATIONS=101:10,102:10|20,103:30 DRY_RUN=1 \\
        bundle exec rake content_records:migrate_from_discipline_batch
  DESC
  task migrate_from_discipline_batch: :environment do
    raw_migrations = ENV['MIGRATIONS'].presence
    raise 'Informe MIGRATIONS=101:10,102:20' if raw_migrations.blank?

    migrations = raw_migrations.split(',').map(&:strip).reject(&:blank?).map do |pair|
      dcr_id, ka_ids = pair.split(':', 2).map(&:strip)
      raise "Par inválido em MIGRATIONS: #{pair}" if dcr_id.blank? || ka_ids.blank?

      [dcr_id.to_i, ka_ids.split('|').map(&:strip).reject(&:blank?).map(&:to_i)]
    end

    dry_run = truthy_env?('DRY_RUN', default: true)
    delete_old = truthy_env?('DELETE_OLD')
    skip_knowledge_area_check = truthy_env?('SKIP_KNOWLEDGE_AREA_CHECK')
    verbose = truthy_env?('VERBOSE')

    total_created = 0
    total_skipped = 0
    total_errors = []

    with_content_records_entity_connection do |entity|
      puts "Entidade: #{entity.name} (#{entity.domain})"
      puts "Modo: #{dry_run ? 'simulação (DRY_RUN)' : 'execução'}"

      migrations.each do |discipline_record_id, knowledge_area_ids|
        puts "\n--- DCR##{discipline_record_id} → KNOWLEDGE_AREA_IDS=#{knowledge_area_ids.join(',')} ---"

        result = DisciplineToKnowledgeAreaContentRecordMigrator.new(
          discipline_record_ids: [discipline_record_id],
          knowledge_area_ids: knowledge_area_ids,
          dry_run: dry_run,
          delete_old: delete_old,
          skip_knowledge_area_check: skip_knowledge_area_check,
          verbose: verbose
        ).call

        total_created += result.created
        total_skipped += result.skipped
        total_errors.concat(result.errors)
      end

      puts "\n=== Resumo ==="
      puts "Criados: #{total_created} | Ignorados (já existiam): #{total_skipped}"
      total_errors.each { |error| puts "ERRO: #{error}" }
    end
  end
end
