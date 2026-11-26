namespace :lesson_plans do
  def lesson_plans_entity
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

  def with_lesson_plans_entity_connection
    entity = lesson_plans_entity

    if Entity.current.present?
      yield entity
    else
      entity.using_connection { yield entity }
    end
  end

  def parse_discipline_lesson_plan_ids
    raw_ids = ENV['DLP_RECORD_IDS'].presence || ENV.fetch('dlp_record_ids', nil)
    raise 'Informe DLP_RECORD_IDS=101,102,103' if raw_ids.blank?

    raw_ids.split(',').map(&:strip).reject(&:blank?).map(&:to_i)
  end

  def parse_lesson_plan_knowledge_area_ids
    raw_ids = ENV['KNOWLEDGE_AREA_IDS'].presence || ENV['KA_IDS'].presence
    return nil if raw_ids.blank?

    raw_ids.split(',').map(&:strip).reject(&:blank?).map(&:to_i)
  end

  def lesson_plans_truthy_env?(key, default: false)
    value = ENV[key]
    return default if value.blank?

    %w[1 true yes sim].include?(value.to_s.downcase)
  end

  def print_lesson_plan_migration_result(result)
    puts "Criados: #{result.created} | Ignorados (já existiam): #{result.skipped}"
    result.errors.each { |error| puts "ERRO: #{error}" }
  end

  desc <<~DESC
    Migra planos de aula por disciplina para plano por área de conhecimento.

    Variáveis:
      DOMAIN ou TENANT          Entidade alvo (obrigatório se não estiver em entity:run)
      DLP_RECORD_IDS            IDs de DisciplineLessonPlan separados por vírgula
      KNOWLEDGE_AREA_IDS        IDs das áreas de destino (opcional; padrão = área da disciplina)
      DRY_RUN                   1 para simular (padrão: 1)
      DELETE_OLD                1 para remover planos por disciplina após migrar (padrão: 0)
      SKIP_KNOWLEDGE_AREA_CHECK 1 para ignorar validação de área da disciplina (padrão: 0)
      VERBOSE                   1 para exibir backtrace completo no terminal

    Exemplos:
      RAILS_ENV=production DOMAIN=escola.gov.br DLP_RECORD_IDS=101,102 DRY_RUN=1 \\
        bundle exec rake lesson_plans:migrate_from_discipline

      RAILS_ENV=production DOMAIN=escola.gov.br DLP_RECORD_IDS=101,102 KNOWLEDGE_AREA_IDS=10 DRY_RUN=0 DELETE_OLD=1 \\
        bundle exec rake "entity:run[lesson_plans:migrate_from_discipline]"
  DESC
  task migrate_from_discipline: :environment do
    discipline_lesson_plan_ids = parse_discipline_lesson_plan_ids
    knowledge_area_ids = parse_lesson_plan_knowledge_area_ids
    dry_run = lesson_plans_truthy_env?('DRY_RUN', default: true)
    delete_old = lesson_plans_truthy_env?('DELETE_OLD')
    skip_knowledge_area_check = lesson_plans_truthy_env?('SKIP_KNOWLEDGE_AREA_CHECK')
    verbose = lesson_plans_truthy_env?('VERBOSE')

    with_lesson_plans_entity_connection do |entity|
      puts "Entidade: #{entity.name} (#{entity.domain})"
      puts "Modo: #{dry_run ? 'simulação (DRY_RUN)' : 'execução'}"
      destination = knowledge_area_ids.present? ? "KNOWLEDGE_AREA_IDS=#{knowledge_area_ids.join(',')}" : 'área da disciplina'
      puts "DLP_RECORD_IDS=#{discipline_lesson_plan_ids.join(',')} → #{destination}"

      result = DisciplineToKnowledgeAreaLessonPlanMigrator.new(
        discipline_lesson_plan_ids: discipline_lesson_plan_ids,
        knowledge_area_ids: knowledge_area_ids,
        dry_run: dry_run,
        delete_old: delete_old,
        skip_knowledge_area_check: skip_knowledge_area_check,
        verbose: verbose
      ).call

      print_lesson_plan_migration_result(result)
    end
  end

  desc <<~DESC
    Migra vários planos de aula por disciplina para áreas diferentes em lote.

    Variáveis:
      DOMAIN ou TENANT  Entidade alvo
      MIGRATIONS        Pares dlp_id:ka_id separados por vírgula (ex: 101:10,102:10,103:20)
                        Use dlp_id:ka_id1|ka_id2 para várias áreas no mesmo plano
      DRY_RUN           1 para simular (padrão: 1)
      DELETE_OLD        1 para remover planos por disciplina após migrar (padrão: 0)
      SKIP_KNOWLEDGE_AREA_CHECK 1 para ignorar validação de área (padrão: 0)
      VERBOSE           1 para exibir backtrace completo no terminal

    Exemplo:
      RAILS_ENV=production DOMAIN=escola.gov.br MIGRATIONS=101:10,102:10|20,103:30 DRY_RUN=1 \\
        bundle exec rake lesson_plans:migrate_from_discipline_batch
  DESC
  task migrate_from_discipline_batch: :environment do
    raw_migrations = ENV['MIGRATIONS'].presence
    raise 'Informe MIGRATIONS=101:10,102:20' if raw_migrations.blank?

    migrations = raw_migrations.split(',').map(&:strip).reject(&:blank?).map do |pair|
      dlp_id, ka_ids = pair.split(':', 2).map(&:strip)
      raise "Par inválido em MIGRATIONS: #{pair}" if dlp_id.blank? || ka_ids.blank?

      [dlp_id.to_i, ka_ids.split('|').map(&:strip).reject(&:blank?).map(&:to_i)]
    end

    dry_run = lesson_plans_truthy_env?('DRY_RUN', default: true)
    delete_old = lesson_plans_truthy_env?('DELETE_OLD')
    skip_knowledge_area_check = lesson_plans_truthy_env?('SKIP_KNOWLEDGE_AREA_CHECK')
    verbose = lesson_plans_truthy_env?('VERBOSE')

    total_created = 0
    total_skipped = 0
    total_errors = []

    with_lesson_plans_entity_connection do |entity|
      puts "Entidade: #{entity.name} (#{entity.domain})"
      puts "Modo: #{dry_run ? 'simulação (DRY_RUN)' : 'execução'}"

      migrations.each do |discipline_lesson_plan_id, knowledge_area_ids|
        puts "\n--- DLP##{discipline_lesson_plan_id} → KNOWLEDGE_AREA_IDS=#{knowledge_area_ids.join(',')} ---"

        result = DisciplineToKnowledgeAreaLessonPlanMigrator.new(
          discipline_lesson_plan_ids: [discipline_lesson_plan_id],
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
