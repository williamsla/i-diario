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

            if total != old_value
              dcr.update_column(:class_number, total)
              count += 1
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
      count = update_class_by_qtd(1, 2025)
      puts "Total de registros atualizados que antes estavam 1: #{count}"
      count = update_class_by_qtd(2, 2025)
      puts "Total de registros atualizados que antes estavam 2: #{count}"
      count = update_class_by_qtd(3, 2025)
      puts "Total de registros atualizados que antes estavam 3: #{count}"
      count = update_class_by_qtd(4, 2025)
      puts "Total de registros atualizados que antes estavam 4: #{count}"
    end
    
    puts "=== Fim da atualização ==="
  end
end
