# 1. recuperar escolas
# 2. recuperar professores
# 3. recuperar etapas


desc "Posting changed avaliations"
task post_avaliations: :environment do
    entity = Entity.active.last
    
    entity.using_connection do
      connection = ActiveRecord::Base.connection

      # schools = connection.select_rows('select id, name from unities where active=true')
      schools = Unity.to_select
      schools.each do |school|
        puts "#{school.id} - #{school.name}"

        Teacher.by_unity_id(school.id).order_by_name.each do |teacher|
          puts "  #{teacher.name} - #{teacher.id}"
        end
      end
      
      ApiPostingTypes.to_a.each_with_index do |postType, index|
        puts postType.last
      end
      # connection.select_rows('select * from users').each do |item|
        # puts item.join(', ')

        # ieducar_api_exam_postings_path(
        #   step_column => step.id, post_type: postType.last
        # )

        # new_permitted_attributes = permitted_attributes.merge!({ author: current_user })
        # new_permitted_attributes = new_permitted_attributes.merge!({ teacher: current_user.current_teacher })
        # new_permitted_attributes = new_permitted_attributes.merge!({ ieducar_api_configuration: IeducarApiConfiguration.current })
        # new_permitted_attributes = new_permitted_attributes.merge!({ status: ApiSynchronizationStatus::STARTED })

        # ieducar_api_exam_posting = IeducarApiExamPosting.create!(new_permitted_attributes)

        # ieducar_api_exam_posting_last = IeducarApiExamPosting.where(new_permitted_attributes.merge({status: ApiSynchronizationStatus::COMPLETED })).last

        # jid = IeducarExamPostingWorker.perform_in(5.seconds, current_entity.id, ieducar_api_exam_posting.id, ieducar_api_exam_posting_last.try(:id), params[:force_posting])

        # WorkerBatch.create!(
        #   main_job_class: 'IeducarExamPostingWorker',
        #   main_job_id: jid,
        #   stateable: ieducar_api_exam_posting
        # )

      # end
    end
  # end
end
