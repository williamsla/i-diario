require 'hexapdf'

desc "Print diary (obrigatório: YEAR= e DOMAIN= ou TENANT=). Ex: YEAR=2024 DOMAIN=escola.gov.br rake print_diary"
task print_diary: :environment do

  DISCIPLINE_LESSON_PLAN_REPORT = "1"
  DISCIPLINE_CONTENT_RECORD = "2"

  def teacher_is_active_in_classroom(connection, classroom_id, teacher_id)
    connection.select_value("SELECT count(x.id) > 0
                              FROM public.teacher_discipline_classrooms x
                              where x.classroom_id = #{classroom_id}
                              and x.teacher_id = #{teacher_id}
                              and x.active = true and x.discarded_at is null")
  end

  def teacher_is_specific_area(connection, classroom_id, teacher_id)
    connection.select_value("SELECT x.allow_absence_by_discipline
                              FROM public.teacher_discipline_classrooms x
                              where x.classroom_id = #{classroom_id}
                              and x.teacher_id = #{teacher_id}
                              and x.active = true and x.discarded_at is null")
  end

  def classroom_has_general_absence(classroom)
    classroom.first_exam_rule.frequency_type == FrequencyTypes::GENERAL
  end

  def classroom_has_opinion_type(classroom)
    classroom.first_exam_rule.opinion_type != OpinionTypes::DONT_USE
  end

  def current_entity_configuration
    cache_key = "EntityConfiguration#"
    @current_entity_configuration ||= Rails.cache.fetch(cache_key, expires_in: 1.day) { EntityConfiguration.first }
  end

  def report_name(prefix, qtd_char=10)
    "/#{prefix}-#{SecureRandom.hex(qtd_char)}.pdf"
  end

  def add_pdf_to_merge(pdfTarget, name, render)
    file_path = "#{Rails.root}/public#{name}"
    
    File.open(file_path, 'wb') do |f|
      f.write(render)
    end

    # last_page_number = pdfTarget.pages.size

    localpdf = HexaPDF::Document.open(file_path)
    localpdf.pages.each {|page| pdfTarget.pages << pdfTarget.import(page)}

    # pdfTarget.outline.add_item("Main") do |main|
    #   main.add_item(name, destination: last_page_number)      
    # end

    File.delete(file_path)
  end

  def merge_pdf(pdfTarget, name, rootPath="#{Rails.root}/public")
    full_path_report_diario = "#{rootPath}#{name}"

    pdfTarget.write(full_path_report_diario, optimize: true)
    
    full_path_report_diario
  end

  def classroom_has_general_absence(classroom)
    classroom.first_exam_rule.frequency_type == FrequencyTypes::GENERAL
  end

  def classroom_has_opinion_type(classroom)
    classroom.first_exam_rule.opinion_type != OpinionTypes::DONT_USE
  end

  def build_by_school_steps(exam_average_report_form, school, teacher, classroom, discipline, year)
    @students_enrollments = exam_average_report_form.students_enrollments
    ExamStepAverageReport.build(
      current_entity_configuration,
      school,
      teacher,
      year,
      classroom,
      Discipline.find(exam_average_report_form.discipline_id),
      exam_average_report_form.steps,
      @students_enrollments
    )
  end

  def build_by_classroom_steps(exam_average_report_form, school, teacher, classroom, discipline, year)
    @students_enrollments = exam_average_report_form.students_enrollments
    ExamStepAverageReport.build(
      current_entity_configuration,
      school,
      teacher,
      year,
      classroom,
      Discipline.find(exam_average_report_form.discipline_id),
      exam_average_report_form.classroom_steps,
      @students_enrollments
    )
  end

  year = ENV.fetch("YEAR") do
    raise "Informe YEAR=. Ex: YEAR=2024 DOMAIN=escola.gov.br rake print_diary"
  end.to_i
  raise "YEAR inválido" if year <= 0
  root = "#{Rails.root}/impressao-diarios/#{year}"
  system("mkdir -p #{root}")

  entity = if ENV["DOMAIN"].present?
             e = Entity.find_by(domain: ENV["DOMAIN"])
             raise "Entidade não encontrada para DOMAIN=#{ENV['DOMAIN']}" unless e
             e
           elsif ENV["TENANT"].present?
             e = Entity.find_by(name: ENV["TENANT"])
             raise "Entidade não encontrada para TENANT=#{ENV['TENANT']}" unless e
             e
           else
             raise "Obrigatório informar DOMAIN= ou TENANT=. Ex: YEAR=2024 DOMAIN=escola.gov.br rake print_diary"
           end

  puts "Imprimindo diários: #{entity.name} (#{entity.domain}), ano #{year}"

  entity.using_connection do
      connection = ActiveRecord::Base.connection

      current_user = User.find_by(login: 'admin')

      # get schools
      Unity.to_select.each do |school|
        puts "","#{school.id} - #{school.name}"

        directory_name = "#{root}/#{school.name}"
        if File.exists?(directory_name)
          next
        else
          Dir.mkdir(directory_name)
        end

        calendars = SchoolCalendar.by_unity_id(school.id).by_year(year)

        unless calendars.any?
          next
        end

        calendar = calendars.first

        classrooms = Classroom.by_unity(school.id).by_year(calendar.year)

        classrooms.each do |classroom|
            puts "\t#{classroom.description} - #{classroom.id}"
        
            @school_calendar_steps = SchoolCalendarStep.where(school_calendar: calendar).ordered    
            @school_calendar_classroom_steps = SchoolCalendarClassroomStep.by_classroom(classroom.id).ordered
            
            if @school_calendar_classroom_steps.any?
              steps = @school_calendar_classroom_steps
              has_steps_by_classroom = true
            else
              steps = @school_calendar_steps
              has_steps_by_classroom = false
            end

            active_enrollment_classrooms = StudentEnrollmentClassroom.by_classroom(classroom.id).active            

            # get teachers
            Teacher.by_unity_id(school.id).by_classroom(classroom.id).by_year(calendar.year).active_query.order_by_name.each do |teacher|
                is_active = teacher_is_active_in_classroom(connection, classroom.id, teacher.id)
                next if is_active == false

                puts "\t\t#{teacher.name} - #{teacher.id}"

                pdfTarget = HexaPDF::Document.new
                      
                fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(
                  teacher.id,
                  school,
                  calendar.year
                )
                disciplines ||= fetch_linked_by_teacher[:disciplines].by_classroom_id(
                  classroom.id
                ).not_descriptor.not_grouper
                
                knowledge_areas = KnowledgeArea.by_teacher(teacher.id)
                                              .by_classroom_id(classroom.id)
                                              .ordered
                
                
                teacher_has_frequency_by_discipline = teacher_is_specific_area(connection, classroom.id, teacher.id)
                if teacher_has_frequency_by_discipline == true
                  aux_disciplines = disciplines
                  class_numbers_array = [1..5] # get all class_numbers
                elsif classroom_has_general_absence(classroom) == true
                  aux_disciplines = [disciplines.first]
                  class_numbers_array = []
                else
                  aux_disciplines = disciplines
                  class_numbers_array = [1..5] # get all class_numbers
                end

                  DiaryCoverReport.build(
                      pdfTarget,
                      current_entity_configuration,
                      school,
                      classroom,
                      '',
                      teacher,
                      calendar.year
                  )

                  @diary_report_form = DiaryReportForm.new(
                      unity_id: school.id,
                      classroom_id: classroom.id,
                      school_calendar_year: calendar.year,
                      discipline_id: disciplines.first.id.presence || 0,
                      teacher_id: teacher.id,
                      start_at: steps.first.start_at,
                      end_at: steps.last.end_at,
                      receive_email_confirmation: false
                  )

                  aux_disciplines.each do |discipline|

                      @attendance_record_report_form = AttendanceRecordReportForm.new(
                        unity_id: school.id,
                        school_calendar_year: calendar.year,
                        classroom_id: classroom.id,
                        discipline_id: discipline.id,
                        period: Periods::FULL,
                        current_teacher_id: teacher.id,
                        start_at: @diary_report_form.start_at,
                        end_at: @diary_report_form.end_at,
                        class_numbers: class_numbers_array,
                        # global_absence: true
                      )
                      
                      @attendance_record_report_form.school_calendar = SchoolCalendar.find_by(
                        unity: @attendance_record_report_form.unity_id,
                        year: calendar.year
                      )
              
                      if @attendance_record_report_form.valid?
                        attendance_record_report = AttendanceRecordReportPortrait.build(
                          current_entity_configuration,
                          school,
                          teacher,
                          calendar.year,
                          @attendance_record_report_form.start_at,
                          @attendance_record_report_form.end_at,
                          @attendance_record_report_form.daily_frequencies,
                          @attendance_record_report_form.enrollment_classrooms_list,
                          [],
                          @attendance_record_report_form.school_calendar,
                          @attendance_record_report_form.second_teacher_signature,
                          @attendance_record_report_form.students_frequencies_percentage,
                          current_user,
                          classroom.description
                        )
                        
                        add_pdf_to_merge(pdfTarget, report_name('frequencia'), attendance_record_report.render)        
                      else
                        Rails.logger.error "Ocorreu um erro ao carregar frequência"        
                      end
                  end # frequency
                  
                  #content
                  disciplines.each do |discipline|

                    continue_loop = true
                    [ContentRecordReportTypes::CONTENT_RECORD, ContentRecordReportTypes::LESSON_PLAN].each do |report_type|
                      
                        if continue_loop == false
                          break
                        end
                    
                        @discipline_lesson_plan_report_form = DisciplineLessonPlanReportForm.new(
                          teacher_id: teacher.id,
                          unity_id: school.id,
                          classroom_id: classroom.id,
                          discipline_id: discipline.id,
                          date_start: @diary_report_form.start_at,
                          date_end: @diary_report_form.end_at
                        )
                
                        @discipline_lesson_plan_report_form.author = PlansAuthors::ALL
                        @discipline_lesson_plan_report_form.report_type = report_type
                
                        if @discipline_lesson_plan_report_form.valid?
                          if report_type == ContentRecordReportTypes::CONTENT_RECORD
                              report = DisciplineContentRecordReport.build(current_entity_configuration,
                                                                                    school,
                                                                                    @discipline_lesson_plan_report_form.date_start,
                                                                                    @discipline_lesson_plan_report_form.date_end,
                                                                                    @discipline_lesson_plan_report_form.discipline_content_record,
                                                                                    teacher,
                                                                                    classroom)
                              report_name = report_name('conteudo') 
                          else
                              report = DisciplineLessonPlanReport.build(current_entity_configuration,
                                                                                    school,
                                                                                    @discipline_lesson_plan_report_form.date_start,
                                                                                    @discipline_lesson_plan_report_form.date_end,
                                                                                    @discipline_lesson_plan_report_form.discipline_lesson_plan,
                                                                                    teacher,
                                                                                    classroom)
                              report_name = report_name('plano-de-aula') 
                          end
                                                                                
                          add_pdf_to_merge(pdfTarget, report_name, report.render)
                          continue_loop = false
                          
                        else
                          puts "Ocorreu um erro ao carregar conteúdos da disciplina"  
                          puts "#{@discipline_lesson_plan_report_form.inspect}"  
                        end
                    end
                  end
            
                  knowledge_areas.each do |knowledge_area|
                    continue_loop = true
                    [ContentRecordReportTypes::CONTENT_RECORD, ContentRecordReportTypes::LESSON_PLAN].each do |report_type|
                        if continue_loop == false
                          break
                        end

                        @knowledge_area_lesson_plan_report_form = KnowledgeAreaLessonPlanReportForm.new(
                          unity_id: school.id,
                          classroom_id: classroom.id,
                          teacher_id: teacher.id,
                          knowledge_area_id: knowledge_area.id,
                          date_start: @diary_report_form.start_at,
                          date_end: @diary_report_form.end_at
                        )
                
                        @knowledge_area_lesson_plan_report_form.author = PlansAuthors::ALL
                        @knowledge_area_lesson_plan_report_form.report_type = report_type
                
                        if @knowledge_area_lesson_plan_report_form.valid?
                          if report_type == ContentRecordReportTypes::CONTENT_RECORD
                              report = KnowledgeAreaContentRecordReport.build(current_entity_configuration,
                                                                                                        @knowledge_area_lesson_plan_report_form.date_start,
                                                                                                        @knowledge_area_lesson_plan_report_form.date_end,
                                                                                                        @knowledge_area_lesson_plan_report_form.knowledge_area_content_record,
                                                                                                        teacher)      
                              report_name = report_name('conteudo')
                          else
                              report = KnowledgeAreaLessonPlanReport.build(current_entity_configuration,
                                                                                            @knowledge_area_lesson_plan_report_form.date_start,
                                                                                            @knowledge_area_lesson_plan_report_form.date_end,
                                                                                            @knowledge_area_lesson_plan_report_form.knowledge_area_lesson_plan,
                                                                                            teacher)      
                              report_name = report_name('plano-de-aula')  
                          end

                          add_pdf_to_merge(pdfTarget, report_name, report.render)
                          continue_loop = false
                        else
                          puts "Ocorreu um erro ao carregar conteúdos da área de conhecimento: #{knowledge_area.description}"
                          puts "#{@knowledge_area_lesson_plan_report_form.inspect}"  
                        end
                    end
                  end

                  # avaliations
                  disciplines.by_score_type(ScoreTypes::NUMERIC).each do |discipline|
                    # if discipline.description.match(/([a-zA-Z]{2}[0-9]{2}){2}/)
                    #   next
                    # end
                    
                    if has_steps_by_classroom == true
                      @exam_average_report_form = ExamAverageReportForm.new(
                        unity_id: school.id,
                        classroom_id: classroom.id,
                        discipline_id: discipline.id,
                        school_calendar_classroom_steps: steps                        
                      )
                    else
                      @exam_average_report_form = ExamAverageReportForm.new(
                        unity_id: school.id,
                        classroom_id: classroom.id,
                        discipline_id: discipline.id,
                        school_calendar_steps: steps
                      )
                    end
            
                    if @exam_average_report_form.valid? 
                      exam_record_report = has_steps_by_classroom == true ? build_by_classroom_steps(@exam_average_report_form, school, teacher, classroom, discipline, calendar.year) : build_by_school_steps(@exam_average_report_form, school, teacher, classroom, discipline, calendar.year)
                      add_pdf_to_merge(pdfTarget, report_name('avaliacao'), exam_record_report.render)
                    else
                      puts "Ocorreu um erro ao carregar avaliações da disciplina"  
                      puts "#{@exam_average_report_form.inspect}"  
                    end
                  end

                  if ConceptualExamReportBatchBuilder.classroom_has_conceptual_score_type?(classroom)
                    ConceptualExamReportBatchBuilder.new(
                      entity_configuration: current_entity_configuration,
                      unity: school,
                      classroom: classroom,
                      teacher_id: teacher.id,
                      start_at: @diary_report_form.start_at,
                      end_at: @diary_report_form.end_at
                    ).each_rendered_report do |render|
                      add_pdf_to_merge(pdfTarget, report_name('avaliacao-conceitual'), render)
                    end
                  end

                  # parecer
                  if classroom_has_opinion_type(classroom) == true
                    @descriptive_form = DescriptiveReportForm.new(
                      classroom_id: classroom.id,
                      start_at: @diary_report_form.start_at,
                      end_at: @diary_report_form.end_at
                    )

                    if @descriptive_form.valid?
                      descriptive_report = DescriptiveReport.build(
                        current_entity_configuration, 
                        school, 
                        calendar.year, 
                        @descriptive_form.fetch_exam_steps, 
                        @descriptive_form.fetch_exam_values, 
                        @descriptive_form.fetch_students, 
                        active_enrollment_classrooms,
                        classroom,
                        @descriptive_form.is_annual,
                        true
                      )
                
                      add_pdf_to_merge(pdfTarget, report_name('parecer'), descriptive_report.render)
                    end
                  end

                  
                  # --
                  filename_diary = report_name("diario#{calendar.year}-#{classroom.description.gsub('/','')}-#{teacher.name.split.first}", 4)
                  filename_diary_full_path = merge_pdf(pdfTarget, filename_diary, directory_name)
            end
        end
          

      end # end school loop
    end # end connection loop

end
