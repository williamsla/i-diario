desc "Posting changed avaliations"
task post_avaliations: :environment do

  def get_last_post_date(connection, post_type, teacher_id, step_number)
    connection.select_value("SELECT max(iaep.created_at)
                              FROM public.ieducar_api_exam_postings iaep
                              LEFT JOIN public.school_calendar_steps scs on scs.id = iaep.school_calendar_step_id
                              LEFT JOIN public.school_calendar_classroom_steps sccs on sccs.id = iaep.school_calendar_classroom_step_id
                              WHERE iaep.post_type='#{post_type}' and iaep.status='completed' and iaep.teacher_id=#{teacher_id}
                              and (
                                    (iaep.school_calendar_step_id is not null and scs.step_number=#{step_number})
                                    or
                                    (iaep.school_calendar_classroom_step_id is not null and sccs.step_number=#{step_number})
                                  )")
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
      Teacher.by_unity_id(school.id).by_year(last_calendar.year).active_query.order_by_name.each do |teacher|
        puts "  #{teacher.name} - #{teacher.id}"

        calendar_steps.each do |step|

          ApiPostingTypes.to_a.each_with_index do |postType, index|
            
            if postType.last == 'absence'
                last_change = connection.select_value("SELECT max(dfs.updated_at) 
                                          FROM public.daily_frequencies df
                                          inner join public.daily_frequency_students dfs on dfs.daily_frequency_id = df.id 
                                          inner join public.classrooms c on c.id = df.classroom_id 
                                          where df.unity_id=#{school.id} and df.owner_teacher_id=#{teacher.id} 
                                                and df.frequency_date between '#{step.start_at}' and '#{step.end_at}'
                                                and c.year=#{last_calendar.year}"
                                        )
            elsif postType.last == 'conceptual_exam'
            elsif postType.last == 'descriptive_exam'
                last_change = connection.select_value("SELECT max(des.updated_at)
                                          FROM public.descriptive_exams de
                                          inner join public.descriptive_exam_students des on des.descriptive_exam_id = de.id 
                                          inner join public.classrooms c on c.id = de.classroom_id
                                          inner join public.teacher_discipline_classrooms tdc on tdc.classroom_id = c.id 
                                          where de.step_number=#{step.step_number} and c.unity_id=#{school.id} and tdc.teacher_id =#{teacher.id}
                                              and c.year=#{last_calendar.year}"
                                        )
            elsif postType.last == 'numerical_exam'
                last_change = connection.select_value("SELECT max(dns.updated_at)
                                          FROM public.avaliations ava
                                          inner join public.classrooms c on c.id = ava.classroom_id
                                          inner join public.daily_notes dn on dn.avaliation_id = ava.id 
                                          inner join public.daily_note_students dns on dns.daily_note_id = dn.id 
                                          inner join public.teacher_discipline_classrooms tdc on tdc.discipline_id = ava.discipline_id 
                                          where tdc.teacher_id=#{teacher.id} and ava.test_date between '#{step.start_at}' and '#{step.end_at}'
                                                and c.year=#{last_calendar.year} and c.unity_id=#{school.id}"
                                        )
            elsif postType.last == 'final_recovery'
                last_change = connection.select_value("SELECT max(rdrs.updated_at) 
                                          FROM public.final_recovery_diary_records frdr 
                                          inner join public.recovery_diary_records rdr on rdr.id = frdr.recovery_diary_record_id 
                                          inner join public.recovery_diary_record_students rdrs on rdrs.recovery_diary_record_id = rdr.id 
                                          inner join public.classrooms c on c.id = rdr.classroom_id
                                          inner join public.teacher_discipline_classrooms tdc on tdc.classroom_id = c.id 
                                          where c.year=#{last_calendar.year} and c.unity_id=#{school.id} 
                                                and tdc.teacher_id=#{teacher.id} and rdr.recorded_at BETWEEN '#{step.start_at}' and '#{step.end_at}'"
                                        )
            elsif postType.last == 'school_term_recovery'
                last_change = connection.select_value("SELECT max(rdrs.updated_at) 
                                          FROM public.recovery_diary_records rdr
                                          inner join public.classrooms c on c.id = rdr.classroom_id 
                                          inner join public.school_term_recovery_diary_records strdr  on strdr.recovery_diary_record_id = rdr.id
                                          inner join public.recovery_diary_record_students rdrs on rdrs.recovery_diary_record_id = rdr.id 
                                          inner join public.teacher_discipline_classrooms tdc on tdc.classroom_id = c.id 
                                          where c.year=#{last_calendar.year} and strdr.step_number=#{step.step_number}
                                              and tdc.teacher_id=#{teacher.id}"
                                        )
            end

            last_post = get_last_post_date(connection, postType.last, teacher.id, step.step_number)

            if last_change != nil
              if last_post == nil or last_change > last_post
                  puts "    etapa #{step.step_number} #{postType.first}: última_mudança #{last_change} X último_envio #{last_post}"
              end
            end

          end

        end
      end
    end
    
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
  end
end
