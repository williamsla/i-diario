# 1. recuperar escolas
# 2. recuperar professores
# 3. recuperar etapas


desc "Posting changed avaliations"
task post_avaliations: :environment do

    def get_last_post_date(connection, post_type, teacher_id, step_number)
      connection.select_rows("SELECT max(iaep.created_at)
                                            FROM public.ieducar_api_exam_postings iaep
                                            LEFT JOIN public.school_calendar_steps scs on scs.id = iaep.school_calendar_step_id
                                            LEFT JOIN public.school_calendar_classroom_steps sccs on sccs.id = iaep.school_calendar_classroom_step_id
                                            WHERE iaep.post_type='#{post_type}' and iaep.status='completed' and iaep.teacher_id=#{teacher_id}
                                            and (
                                                  (iaep.school_calendar_step_id is not null and scs.step_number=#{step_number})
                                                  or
                                                  (iaep.school_calendar_classroom_step_id is not null and sccs.step_number=#{step_number})
                                                )").first.first
    end

    entity = Entity.active.last
    
    entity.using_connection do
      connection = ActiveRecord::Base.connection

      # get schools
      Unity.to_select.each do |school|
        puts "","#{school.id} - #{school.name}"

        last_calendar = SchoolCalendar.by_unity_id(school.id).ordered.first

        calendar_steps = SchoolCalendarStep.by_school_calendar_id(last_calendar.id).by_unity(school.id).ordered
        # calendar_classroom_steps = SchoolCalendarClassroomStep.by_school_calendar_id(last_calendar.id).ordered
        # steps = calendar_steps + calendar_classroom_steps
        
        # get teachers
        Teacher.by_unity_id(school.id).order_by_name.each do |teacher|
          puts "  #{teacher.name} - #{teacher.id}"

          calendar_steps.each do |step|

            ApiPostingTypes.to_a.each_with_index do |postType, index|
              
              if postType.last == 'absence'
              elsif postType.last == 'conceptual_exam'
              elsif postType.last == 'descriptive_exam'
                  last_change = connection.select_rows("SELECT max(des.updated_at)
                                            FROM public.descriptive_exams de
                                            inner join public.descriptive_exam_students des on des.descriptive_exam_id = de.id 
                                            inner join public.classrooms c on c.id = de.classroom_id
                                            inner join public.teacher_discipline_classrooms tdc on tdc.classroom_id = c.id 
                                            where de.step_number=#{step.step_number} and c.unity_id=#{school.id} and tdc.teacher_id =#{teacher.id}
                                                and c.year=#{last_calendar.year}"
                                          ).first.first

              elsif postType.last == 'numerical_exam'
                  last_change = connection.select_rows("SELECT max(dns.updated_at)
                                            FROM public.avaliations ava
                                            inner join public.classrooms c on c.id = ava.classroom_id
                                            inner join public.daily_notes dn on dn.avaliation_id = ava.id 
                                            inner join public.daily_note_students dns on dns.daily_note_id = dn.id 
                                            inner join public.teacher_discipline_classrooms tdc on tdc.discipline_id = ava.discipline_id 
                                            where tdc.teacher_id=#{teacher.id} and ava.test_date between '#{step.start_at}' and '#{step.end_at}'
                                                  and c.year=#{last_calendar.year} and c.unity_id=#{school.id}"
                                          ).first.first
              elsif postType.last == 'final_recovery'
              elsif postType.last == 'school_term_recovery'
              end

              last_post = get_last_post_date(connection, postType.last, teacher.id, step.step_number)

                  if last_change != nil
                    if last_post == nil or last_change > last_post
                        puts "    #{postType.last}: etapa #{step.step_number} última_mudança #{last_change} X último_envio #{last_post}"
                    end
                  end

            end

          end
          # exit

          # puts "recuperando envios do professor"
          # IeducarApiExamPosting.by_teacher_id(teacher.id).each do |posting|
            # puts posting.inspect
          # end
        end
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
