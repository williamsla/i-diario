namespace :post_avaliations do

  desc "Posting changed avaliations (obrigatório: DOMAIN= ou TENANT=)"
  task init: :environment do

    def get_last_post_date(connection, post_type, teacher_id, step_number)
      if post_type == 'final_recovery'
        # Para recuperação final, não filtra por etapa, busca o último envio independente da etapa
        connection.select_value("SELECT max(iaep.created_at)
                                  FROM public.ieducar_api_exam_postings iaep
                                  WHERE iaep.post_type='#{post_type}' and iaep.status='completed' and iaep.teacher_id=#{teacher_id}")
      else
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
    end

    def counting_started_postings(connection)
      connection.select_value("SELECT count(iaep.id)
                                FROM public.ieducar_api_exam_postings iaep
                                WHERE iaep.status = '#{ApiSynchronizationStatus::STARTED}'")
    end

    def cancel_started_postings(connection)
      connection.execute("UPDATE public.ieducar_api_exam_postings 
                            SET status = '#{ApiSynchronizationStatus::ERROR}' 
                            WHERE status = '#{ApiSynchronizationStatus::STARTED}'")
      puts "\t\t\t cancelando envios que estão em andamento"
    end

    def is_the_weekend?
      today = Date.current
      today.saturday? || today.sunday?
    end

    def is_dawn?
      current_time = Time.current
      current_time.hour < 6
    end

    def validate_started_postings(connection)
      time_waiting_finish_postings = 5.minutes
      maximum_waiting_time = 2 * time_waiting_finish_postings
      time_awaited = 0

      loop do
        qtd_postings = counting_started_postings(connection)
        if qtd_postings > 10
          
          puts "\t\t\t aguardando #{time_waiting_finish_postings} minutos para diminuir quantidade de envios"
          sleep(time_waiting_finish_postings)
          time_awaited += time_waiting_finish_postings

          if time_awaited > maximum_waiting_time
            cancel_started_postings(connection)
            break
          end
        else
          break
        end
      end
    end

    def sync(entity, step, post_type, author, teacher)
      
      new_permitted_attributes = {}
      if step.instance_of? SchoolCalendarStep
        new_permitted_attributes = new_permitted_attributes.merge!({ school_calendar_step: step })
      else 
        new_permitted_attributes = new_permitted_attributes.merge!({ school_calendar_classroom_step: step })
      end
      new_permitted_attributes = new_permitted_attributes.merge!({ post_type: post_type })
      new_permitted_attributes = new_permitted_attributes.merge!({ author: author })
      new_permitted_attributes = new_permitted_attributes.merge!({ teacher: teacher })
      new_permitted_attributes = new_permitted_attributes.merge!({ ieducar_api_configuration: IeducarApiConfiguration.current })
      new_permitted_attributes = new_permitted_attributes.merge!({ status: ApiSynchronizationStatus::STARTED })
      
      ieducar_api_exam_posting_started = IeducarApiExamPosting.where(new_permitted_attributes).last
      if ieducar_api_exam_posting_started != nil
        puts '      Já existe um envio em andamento'
        return -1
      end
      
      ieducar_api_exam_posting = IeducarApiExamPosting.create!(new_permitted_attributes)            
      ieducar_api_exam_posting_last = IeducarApiExamPosting.where(new_permitted_attributes.merge({status: ApiSynchronizationStatus::COMPLETED })).last

      jid = IeducarExamPostingWorker.perform_in(5.seconds, entity.id, ieducar_api_exam_posting.id, ieducar_api_exam_posting_last.try(:id), false)

      WorkerBatch.create!(
        main_job_class: 'IeducarExamPostingWorker',
        main_job_id: jid,
        stateable: ieducar_api_exam_posting
      )

      return ieducar_api_exam_posting.id
    end

    def start(order)
      has_change = false

      entity = if ENV["DOMAIN"].present?
                 e = Entity.find_by(domain: ENV["DOMAIN"])
                 raise "Entidade não encontrada para DOMAIN=#{ENV['DOMAIN']}" unless e
                 e
               elsif ENV["TENANT"].present?
                 e = Entity.find_by(name: ENV["TENANT"])
                 raise "Entidade não encontrada para TENANT=#{ENV['TENANT']}" unless e
                 e
               else
                 raise "Via rake é obrigatório informar DOMAIN= ou TENANT=. Ex: DOMAIN=escola.gov.br rake post_avaliations:init"
               end

      entity.using_connection do
        connection = ActiveRecord::Base.connection

        @admin_user = User.find_by(login: 'admin')

        count_posting_active = 0

        # get schools
        if order == 'asc'
          schools = Unity.to_select
        else
          schools = Unity.to_select_desc
        end
        qtd_schools = schools.count

        schools.each_with_index do |school, index|
          puts "","[#{index+1}/#{qtd_schools}] #{school.id} - #{school.name}"
          puts "#{Time.current.strftime('%d/%m/%Y %H:%M:%S')}"

          calendars = SchoolCalendar.by_unity_id(school.id).only_opened_years.ordered
          calendars.each do |calendar|
            ## TODO: remover a verificação do ano letivo quando todos estiverem finalizados
            if calendar == nil || calendar.year < 2024
              next
            end

            calendar_steps = SchoolCalendarStep.by_school_calendar_id(calendar.id).by_unity(school.id).ordered
            
            # get teachers
            Teacher.by_unity_id(school.id).by_year(calendar.year).active_query.order_by_name.each do |teacher|
              puts "\t #{teacher.name} - #{teacher.id}"
              steps = calendar_steps

              do_break_teacher_loop = false

              # get classrooms that do not follow the standard school year
              TeacherDisciplineClassroom.by_teacher_id(teacher.id).by_year(calendar.year).each do |tdc|
                calendar_classroom_steps = SchoolCalendarClassroomStep.by_school_calendar_id(calendar.id).by_classroom(tdc.classroom.id)
                steps = steps + calendar_classroom_steps
              end

              steps = steps.uniq()

              steps.each do |step|

                next if do_break_teacher_loop

                ApiPostingTypes.to_a.each_with_index do |postType, index|
                  
                  if postType.last == 'absence' && is_dawn?
                      last_change = connection.select_value("SELECT max(dfs.updated_at) 
                                                FROM public.daily_frequencies df
                                                inner join public.daily_frequency_students dfs on dfs.daily_frequency_id = df.id 
                                                inner join public.classrooms c on c.id = df.classroom_id 
                                                where df.unity_id=#{school.id} and df.owner_teacher_id=#{teacher.id} 
                                                      and df.frequency_date between '#{step.start_at}' and '#{step.end_at}'
                                                      and c.year=#{calendar.year}"
                                              )
                  elsif postType.last == 'conceptual_exam'
                      last_change = connection.select_value("SELECT max(cev.updated_at)
                                                FROM public.conceptual_exams ce
                                                inner join public.conceptual_exam_values cev on cev.conceptual_exam_id = ce.id 
                                                inner join public.classrooms c on c.id = ce.classroom_id 
                                                inner join public.teacher_discipline_classrooms tdc on tdc.classroom_id = c.id and tdc.classroom_id = c.id
                                                where ce.step_number=#{step.step_number} and c.unity_id=#{school.id} and tdc.teacher_id =#{teacher.id}
                                                    and c.year=#{calendar.year}"
                                              )
                  elsif postType.last == 'descriptive_exam'
                      last_change = connection.select_value("SELECT max(des.updated_at)
                                                FROM public.descriptive_exams de
                                                inner join public.descriptive_exam_students des on des.descriptive_exam_id = de.id 
                                                inner join public.classrooms c on c.id = de.classroom_id
                                                inner join public.teacher_discipline_classrooms tdc on tdc.classroom_id = c.id and tdc.classroom_id = c.id
                                                where de.step_number=#{step.step_number} and c.unity_id=#{school.id} and tdc.teacher_id =#{teacher.id}
                                                    and c.year=#{calendar.year}"
                                              )
                  elsif postType.last == 'numerical_exam'
                      last_change = connection.select_value("SELECT max(dns.updated_at)
                                                FROM public.avaliations ava
                                                inner join public.classrooms c on c.id = ava.classroom_id
                                                inner join public.daily_notes dn on dn.avaliation_id = ava.id 
                                                inner join public.daily_note_students dns on dns.daily_note_id = dn.id 
                                                inner join public.teacher_discipline_classrooms tdc on tdc.discipline_id = ava.discipline_id and tdc.classroom_id = c.id
                                                where tdc.teacher_id=#{teacher.id} and ava.test_date between '#{step.start_at}' and '#{step.end_at}'
                                                      and c.year=#{calendar.year} and c.unity_id=#{school.id}"
                                              )
                  elsif postType.last == 'final_recovery'
                      last_change = connection.select_value("SELECT max(rdrs.updated_at) 
                                                FROM public.final_recovery_diary_records frdr 
                                                inner join public.recovery_diary_records rdr on rdr.id = frdr.recovery_diary_record_id 
                                                inner join public.recovery_diary_record_students rdrs on rdrs.recovery_diary_record_id = rdr.id 
                                                inner join public.classrooms c on c.id = rdr.classroom_id
                                                inner join public.teacher_discipline_classrooms tdc on tdc.classroom_id = c.id and tdc.classroom_id = c.id
                                                where c.year=#{calendar.year} and c.unity_id=#{school.id} 
                                                      and tdc.teacher_id=#{teacher.id} and frdr.school_calendar_id=#{calendar.id}"
                                              )
                  elsif postType.last == 'school_term_recovery'
                      last_change = connection.select_value("SELECT max(rdrs.updated_at) 
                                                FROM public.recovery_diary_records rdr
                                                inner join public.classrooms c on c.id = rdr.classroom_id 
                                                inner join public.school_term_recovery_diary_records strdr  on strdr.recovery_diary_record_id = rdr.id
                                                inner join public.recovery_diary_record_students rdrs on rdrs.recovery_diary_record_id = rdr.id 
                                                inner join public.teacher_discipline_classrooms tdc on tdc.classroom_id = c.id and tdc.classroom_id = c.id
                                                where c.year=#{calendar.year} and strdr.step_number=#{step.step_number}
                                                    and tdc.teacher_id=#{teacher.id}"
                                              )
                  else
                    next
                  end

                  last_post = get_last_post_date(connection, postType.last, teacher.id, step.step_number)

                  if last_change != nil
                    if last_post == nil or last_change > last_post

                        has_change = true
                        
                        validate_started_postings(connection)
                        
                        puts "\t\t etapa #{step.step_number} #{postType.first}: última_mudança #{last_change} X último_envio #{last_post}"
                        
                        posting_id = sync(entity, step, postType.last, @admin_user, teacher)

                        if posting_id == -1
                          next
                        end
                        
                        
                        # verificando se o worker finalizou antes de enviar a próxima etapa
                        count=0

                        loop do
                          time_sleep = 30.seconds
                          puts "\t\t\t aguardando #{time_sleep} segundos até o posting id #{posting_id} finalizar"                      
                          sleep(time_sleep)

                          posting = IeducarApiExamPosting.find(posting_id)
                          
                          if posting.status != ApiSynchronizationStatus::STARTED
                            do_break_teacher_loop = false # deve seguir para os proximos envios do professor
                            break 
                          elsif count == 10 # tempo equivalente a 5 minutos
                            do_break_teacher_loop = true # deve abandonar o loop do professor

                            posting.add_error!(
                              I18n.t('ieducar_api.error.messages.post_error'),
                              'Processo parado pelo sistema pois demorou mais que o esperado.'
                            )
                            posting.finish!

                            break
                          end
                          
                          count=count+1
                        end
                    end
                  end                
                end
              end
            end
          end
        end # end school loop
      end # end connection loop

      puts "==> FIM <=="
      return has_change
    end



    # init script
    loop do
      # cancel any ongoing synchronizations
      Rake::Task["ieducar_api:cancel"].reenable
      Rake::Task["ieducar_api:cancel"].invoke
      
      order = ENV['ORDER'] || 'asc'

      was_changed = start(order)

      if was_changed == false
        puts "\n\t não houve mudanças desde a última sincronização.\n\t Aguardando 10 minutos antes de fazer uma nova sincronização.\n"
        sleep(10.minutes)
      else
        sleep(1.minutes)
      end
    end
  end

end
