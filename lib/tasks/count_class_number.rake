# bundle exec rake aulas:atualizar
namespace :aulas do
  desc "Atualiza class_number com base no quadro de horários (lessons_boards) e na data do conteúdo"
  
  task atualizar: :environment do
    def update_class_by_qtd(old_value, year)
      count = 0
      DisciplineContentRecord.joins(:content_record)
        .where("class_number IS NULL OR class_number = ?", old_value)
        .where("EXTRACT(YEAR FROM content_records.record_date) = ?", year)
        .find_each do |dcr|
            cr = dcr.content_record
            
            turma_id = cr.classroom_id
            disciplina_id = dcr.discipline_id
            data = cr.record_date

            next unless data.present?

            total = LessonBoardsFetcher.new(nil).count_lessons(turma_id, disciplina_id, data)

            if total > 0 && total != old_value
              dcr.update_column(:class_number, total)
              count += 1
            end
      end

      count
    end

    def update_sabados_letivos(year)
      # Carrega as datas dos sábados letivos do arquivo de configuração
      config_path = Rails.root.join('config', 'sabados_letivos.yml')
      sabados_letivos_map = if File.exist?(config_path)
        YAML.load_file(config_path) || {}
      else
        {}
      end

      return 0 if sabados_letivos_map.empty?

      # Converte as chaves (strings de data) para objetos Date
      sabados_letivos_dates = sabados_letivos_map.keys.map { |date_str| Date.parse(date_str) }
      
      # Filtra apenas as datas do ano especificado
      sabados_letivos_dates = sabados_letivos_dates.select { |date| date.year == year }

      return 0 if sabados_letivos_dates.empty?

      puts "Encontradas #{sabados_letivos_dates.count} datas de sábados letivos para o ano #{year}"
      puts "Datas: #{sabados_letivos_dates.map { |d| d.strftime('%d/%m/%Y') }.join(', ')}"

      count = 0
      fetcher = LessonBoardsFetcher.new(nil)

      # Busca todos os registros feitos nas datas de sábados letivos
      DisciplineContentRecord.joins(:content_record)
        .where("EXTRACT(YEAR FROM content_records.record_date) = ?", year)
        .where("content_records.record_date IN (?)", sabados_letivos_dates)
        .find_each do |dcr|
          cr = dcr.content_record
          
          turma_id = cr.classroom_id
          disciplina_id = dcr.discipline_id
          data = cr.record_date

          next unless data.present?
          next unless data.saturday? # Garante que é sábado
          next unless sabados_letivos_dates.include?(data) # Garante que está na lista configurada

          total = fetcher.count_lessons(turma_id, disciplina_id, data)

          if total > 0
            old_value = dcr.class_number
            dcr.update_column(:class_number, total)
            count += 1
            puts "  Atualizado: Turma #{turma_id}, Disciplina #{disciplina_id}, Data #{data.strftime('%d/%m/%Y')}, class_number: #{old_value} -> #{total}"
          end
        end

      count
    end
    
    puts "=== Atualizando class_number (somente NULL ou 0) ==="

    entity = Entity.active.last
    
    entity.using_connection do
      connection = ActiveRecord::Base.connection

      count = update_class_by_qtd(0, 2025)
      puts "Total de registros atualizados que antes estavam 0 ou NULL: #{count}"
      
      # temporary - updating specific values
      # count = update_class_by_qtd(1, 2025)
      # puts "Total de registros atualizados que antes estavam 1: #{count}"
      # count = update_class_by_qtd(2, 2025)
      # puts "Total de registros atualizados que antes estavam 2: #{count}"
      # count = update_class_by_qtd(3, 2025)
      # puts "Total de registros atualizados que antes estavam 3: #{count}"
      # count = update_class_by_qtd(4, 2025)
      # puts "Total de registros atualizados que antes estavam 4: #{count}"
    end
    
    puts "=== Fim da atualização ==="
  end

  desc "Reconta class_number para todos os registros feitos em sábados letivos"
  task recontar_sabados_letivos: :environment do
    def update_sabados_letivos(year)
      # Carrega as datas dos sábados letivos do arquivo de configuração
      config_path = Rails.root.join('config', 'sabados_letivos.yml')
      sabados_letivos_map = if File.exist?(config_path)
        YAML.load_file(config_path) || {}
      else
        {}
      end

      if sabados_letivos_map.empty?
        puts "ERRO: Arquivo de configuração de sábados letivos não encontrado ou vazio!"
        puts "Caminho: #{config_path}"
        return 0
      end

      # Converte as chaves (strings de data) para objetos Date
      sabados_letivos_dates = sabados_letivos_map.keys.map { |date_str| Date.parse(date_str) }
      
      # Filtra apenas as datas do ano especificado
      sabados_letivos_dates = sabados_letivos_dates.select { |date| date.year == year }

      if sabados_letivos_dates.empty?
        puts "Nenhuma data de sábado letivo encontrada para o ano #{year}"
        return 0
      end

      puts "=== Reconta sábados letivos do ano #{year} ==="
      puts "Encontradas #{sabados_letivos_dates.count} datas de sábados letivos:"
      sabados_letivos_dates.sort.each do |date|
        weekday = sabados_letivos_map[date.strftime("%Y-%m-%d")]
        puts "  - #{date.strftime('%d/%m/%Y')} (equivalente a #{weekday})"
      end
      puts ""

      count = 0
      fetcher = LessonBoardsFetcher.new(nil)

      # Busca todos os registros feitos nas datas de sábados letivos
      DisciplineContentRecord.joins(:content_record)
        .where("EXTRACT(YEAR FROM content_records.record_date) = ?", year)
        .where("content_records.record_date IN (?)", sabados_letivos_dates)
        .find_each do |dcr|
          cr = dcr.content_record
          
          turma_id = cr.classroom_id
          disciplina_id = dcr.discipline_id
          data = cr.record_date

          next unless data.present?
          next unless data.saturday? # Garante que é sábado
          next unless sabados_letivos_dates.include?(data) # Garante que está na lista configurada

          total = fetcher.count_lessons(turma_id, disciplina_id, data)

          if total > 0
            old_value = dcr.class_number
            dcr.update_column(:class_number, total)
            count += 1
            puts "  ✓ Atualizado: Turma #{turma_id}, Disciplina #{disciplina_id}, Data #{data.strftime('%d/%m/%Y')}, class_number: #{old_value || 'NULL'} -> #{total}"
          else
            puts "  ⚠ Sem aulas encontradas: Turma #{turma_id}, Disciplina #{disciplina_id}, Data #{data.strftime('%d/%m/%Y')}"
          end
        end

      count
    end

    entity = Entity.active.last
    
    entity.using_connection do
      year = 2025
      count = update_sabados_letivos(year)
      puts ""
      puts "=== Total de registros de sábados letivos atualizados: #{count} ==="
    end
  end
end
