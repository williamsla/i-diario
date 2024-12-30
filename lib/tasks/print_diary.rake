require 'hexapdf'

desc "Print diary"
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

  def build_by_school_steps(exam_average_report_form, teacher, classroom, discipline, year, steps)
    @students_enrollments ||= exam_average_report_form.students_enrollments
    ExamStepAverageReport.build(
      current_entity_configuration,
      teacher,
      year,
      classroom,
      Discipline.find(exam_average_report_form.discipline_id),
      steps,
      @students_enrollments
    )
  end

  
  year = 2024
  root = "#{Rails.root}/impressao-diarios/#{year}"
  system("mkdir -p #{root}")

  entity = Entity.active.last
    
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

        calendar = SchoolCalendar.by_unity_id(school.id).by_year(year).first
          
        classrooms = Classroom.by_unity(school.id).by_year(calendar.year)

        classrooms.each do |classroom|
            puts "\t#{classroom.description} - #{classroom.id}"
            steps = SchoolCalendarClassroomStep.by_school_calendar_id(calendar.id).by_classroom(classroom.id)
            has_steps_by_classroom = true
            if steps.blank?
                steps = SchoolCalendarStep.by_school_calendar_id(calendar.id).by_unity(school.id).ordered
                has_steps_by_classroom = false
            end

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
                      discipline_id: disciplines.first.id,
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
                    @discipline_lesson_plan_report_form = DisciplineLessonPlanReportForm.new(
                      teacher_id: teacher.id,
                      unity_id: school.id,
                      classroom_id: classroom.id,
                      discipline_id: discipline.id,
                      date_start: @diary_report_form.start_at,
                      date_end: @diary_report_form.end_at
                    )
            
                    @discipline_lesson_plan_report_form.author = PlansAuthors::ALL
                    @discipline_lesson_plan_report_form.report_type = DISCIPLINE_CONTENT_RECORD
            
                    if @discipline_lesson_plan_report_form.valid?
                      lesson_plan_report = DisciplineContentRecordReport.build(current_entity_configuration,
                                                                            school,
                                                                            @discipline_lesson_plan_report_form.date_start,
                                                                            @discipline_lesson_plan_report_form.date_end,
                                                                            @discipline_lesson_plan_report_form.discipline_content_record,
                                                                            teacher,
                                                                            classroom)
                                                                            
                      add_pdf_to_merge(pdfTarget, report_name('conteudo'), lesson_plan_report.render)
                      
                    else
                      puts "Ocorreu um erro ao carregar conteúdos da disciplina"  
                      puts "#{@discipline_lesson_plan_report_form.inspect}"  
                    end
                  end
            
                  knowledge_areas.each do |knowledge_area|
                    @knowledge_area_lesson_plan_report_form = KnowledgeAreaLessonPlanReportForm.new(
                      unity_id: school.id,
                      classroom_id: classroom.id,
                      teacher_id: teacher.id,
                      knowledge_area_id: knowledge_area.id,
                      date_start: @diary_report_form.start_at,
                      date_end: @diary_report_form.end_at
                    )
            
                    @knowledge_area_lesson_plan_report_form.author = PlansAuthors::ALL
                    @knowledge_area_lesson_plan_report_form.report_type = ContentRecordReportTypes::CONTENT_RECORD
            
                    if @knowledge_area_lesson_plan_report_form.valid?
                      knowledge_area_lesson_plan_report = KnowledgeAreaContentRecordReport.build(current_entity_configuration,
                                                                                                 @knowledge_area_lesson_plan_report_form.date_start,
                                                                                                 @knowledge_area_lesson_plan_report_form.date_end,
                                                                                                 @knowledge_area_lesson_plan_report_form.knowledge_area_content_record,
                                                                                                 teacher)      
                      add_pdf_to_merge(pdfTarget, report_name('conteudo'), knowledge_area_lesson_plan_report.render)
                    else
                      puts "Ocorreu um erro ao carregar conteúdos da área de conhecimento: #{knowledge_area.description}"
                      puts "#{@knowledge_area_lesson_plan_report_form.inspect}"  
                    end
                  end

                  # avaliations
                  disciplines.by_score_type(ScoreTypes::NUMERIC).each do |discipline|
                    # if discipline.description.match(/([a-zA-Z]{2}[0-9]{2}){2}/)
                    #   next
                    # end
                    
                    @exam_average_report_form = ExamAverageReportForm.new(
                      unity_id: school.id,
                      classroom_id: classroom.id,
                      discipline_id: discipline.id                      
                    )

                    if has_steps_by_classroom == true
                      @exam_average_report_form.school_calendar_classroom_steps = steps
                    else
                      @exam_average_report_form.school_calendar_steps = steps
                    end
            
                    if @exam_average_report_form.valid? 
                      exam_record_report = build_by_school_steps(@exam_average_report_form, teacher, classroom, discipline, calendar.year, steps)
                      add_pdf_to_merge(pdfTarget, report_name('avaliacao'), exam_record_report.render)
                    else
                      puts "Ocorreu um erro ao carregar avaliações da disciplina"  
                      puts "#{@exam_average_report_form.inspect}"  
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
                        @descriptive_form.fetch_exam_values, 
                        @descriptive_form.fetch_students, 
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
