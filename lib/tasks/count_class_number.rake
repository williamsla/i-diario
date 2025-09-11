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

            # Ruby wday: domingo=0..sábado=6 → banco: segunda=1..domingo=7
            # dia_semana = data.wday # numero do dia da semana
            dia_semana_nome = data.strftime("%A").downcase # nome do dia da semana

            total_aulas = ActiveRecord::Base.connection.exec_query(<<-SQL).first&.dig("total_aulas") || 0
              SELECT COUNT(lbl.id) AS total_aulas
              FROM lessons_boards lb
              INNER JOIN classrooms_grades cg ON cg.id = lb.classrooms_grade_id and cg.discarded_at IS NULL
              INNER JOIN lessons_board_lessons lbl
                ON lbl.lessons_board_id = lb.id
              INNER JOIN lessons_board_lesson_weekdays lblw
                ON lblw.lessons_board_lesson_id = lbl.id
              INNER JOIN teacher_discipline_classrooms tdc ON tdc.classroom_id = cg.classroom_id
                AND tdc.id = lblw.teacher_discipline_classroom_id
                AND tdc.discarded_at IS NULL
              WHERE cg.classroom_id = #{turma_id}
                AND lblw.weekday = '#{dia_semana_nome}'
                AND tdc.discipline_id = #{disciplina_id}
            SQL

            if total_aulas > 0 && total_aulas <= 3              
              dcr.update_column(:class_number, total_aulas)
              count += 1
            end

      end

      puts "Total de registros atualizados: #{count}"
    end
    
    puts "=== Fim da atualização ==="
  end
end
