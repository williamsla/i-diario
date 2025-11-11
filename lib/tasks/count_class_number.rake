# bundle exec rake aulas:atualizar
namespace :aulas do
  desc "Atualiza class_number com base no quadro de horários (lessons_boards) e na data do conteúdo"
  
  task atualizar: :environment do
    puts "=== Atualizando class_number (somente NULL ou 0) ==="

    entity = Entity.active.last
    
    entity.using_connection do
      connection = ActiveRecord::Base.connection

      count =0
      DisciplineContentRecord.joins(:content_record)
        .where("class_number IS NULL OR class_number = 0")
        .where("EXTRACT(YEAR FROM content_records.record_date) = ?", 2025)
        .find_each do |dcr|
            cr = dcr.content_record
            
            turma_id = cr.classroom_id
            disciplina_id = dcr.discipline_id
            data = cr.record_date

            next unless data.present?

            total_aulas = LessonBoardsFetcher.new(nil).count_lessons(turma_id, disciplina_id, data)

            if total_aulas > 0 && total_aulas < 4
              dcr.update_column(:class_number, total_aulas)
              count += 1
            end
      end
      puts "Total de registros atualizados que antes estavam 0 ou NULL: #{count}"
      
      count =0
      DisciplineContentRecord.joins(:content_record)
        .where("class_number IS NULL OR class_number = 4")
        .where("EXTRACT(YEAR FROM content_records.record_date) = ?", 2025)
        .find_each do |dcr|
            cr = dcr.content_record
            
            turma_id = cr.classroom_id
            disciplina_id = dcr.discipline_id
            data = cr.record_date

            next unless data.present?

            total_aulas = LessonBoardsFetcher.new(nil).count_lessons(turma_id, disciplina_id, data)

            if total_aulas < 4
              dcr.update_column(:class_number, total_aulas)
              count += 1
            end
      end

      
      
      puts "Total de registros atualizados que antes estavam 4: #{count}"
    end
    
    puts "=== Fim da atualização ==="
  end
end
