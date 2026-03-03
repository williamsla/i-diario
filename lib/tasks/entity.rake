namespace :entity do
  # Roda uma rake task apenas para um domínio/entidade específico.
  # Uso: DOMAIN=escola.municipio.gov.br rake "entity:run[teaching_plans:copy_all]"
  #  ou: TENANT=nome_da_entidade rake "entity:run[teaching_plans:copy_all]"
  desc "Run a task for a single entity (use DOMAIN= or TENANT=)"
  task :run, [:task_name] => :environment do |_t, args|
    raise "Informe DOMAIN= ou TENANT= e o nome da task. Ex: DOMAIN=escola.gov.br rake \"entity:run[teaching_plans:copy_all]\"" if args[:task_name].blank?

    entity = if ENV["DOMAIN"].present?
               Entity.find_by(domain: ENV["DOMAIN"])
             elsif ENV["TENANT"].present?
               Entity.find_by(name: ENV["TENANT"])
             else
               nil
             end

    unless entity
      list = Entity.pluck(:name, :domain).first(5).map { |n, d| "#{n} (#{d})" }.join(", ")
      list += "..." if Entity.count > 5
      raise "Entidade não encontrada. Use DOMAIN=host ou TENANT=nome_entidade. Exemplos: #{list}"
    end

    puts "Executando #{args[:task_name]} para entidade: #{entity.name} (#{entity.domain})"
    entity.using_connection do
      Rake::Task[args[:task_name]].invoke
    end
  end

  desc "Entity Setup"
  task setup: :environment do
    creator = EntityCreator.new(ENV)

    creator.setup

    puts creator.status
  end

  desc "Enable Entity"
  task enable: :environment do
    entity_status_manager = EntityStatusManager.new(ENV)

    entity_status_manager.enable

    puts entity_status_manager.status
  end

  desc "Disable Entity"
  task disable: :environment do
    entity_status_manager = EntityStatusManager.new(ENV)

    entity_status_manager.disable

    puts entity_status_manager.status
  end

  namespace :admin do
    desc "Create Admin User"
    task create: :environment do
      admin_user_creator = AdminUserCreator.new(ENV)

      admin_user_creator.create

      puts admin_user_creator.status
    end
  end
end
