class DiaryReportController < ApplicationController
    DISCIPLINE_LESSON_PLAN_REPORT = "1"
    DISCIPLINE_CONTENT_RECORD = "2"
  
    before_action :require_current_classroom, only: [:form, :lesson_plan_report, :content_record_report]
    before_action :require_current_teacher
  
    def form
      @steps = steps_fetcher.steps
      set_options_by_user
      set_school_calendars

      @diary_report_form = DiaryReportForm.new(
        unity_id: current_unity.id,
        classroom_id: current_user_classroom.id,
        school_calendar_year: current_school_year,
        discipline_id: current_user_discipline.id,
        teacher_id: current_teacher.id,
        start_at: @steps.first.start_at,
        end_at: @steps.last.end_at,
        receive_email_confirmation: true
      )
    end

    def teacher_allow_absence_by_discipline?
      @teacher_allow_absence_by_discipline ||= begin
        value = TeacherDisciplineClassroom.by_classroom(current_user_classroom.id)
                                          .by_teacher_id(current_teacher.id)
                                          .by_discipline_id(current_user_discipline.id)
                                          .first
                                          &.allow_absence_by_discipline
        value.to_i == 1
      end
    end

    def classroom_has_general_absence(classroom)
      classroom.first_exam_rule.frequency_type == FrequencyTypes::GENERAL
    end

    def classroom_has_opinion_type(classroom)
      classroom.first_exam_rule.opinion_type != OpinionTypes::DONT_USE
    end
  
    def print_report
      set_options_by_user
      set_school_calendars

      my_logger = Logger.new("#{Rails.root}/log/my.log")
      my_logger.info("--------------------------------\nINICIANDO IMPRESSÃO DO DIÁRIO")
      tempo_total = 0

      @diary_report_form = DiaryReportForm.new(resource_params)

      pdfTarget = HexaPDF::Document.new
      
      coverReport = DiaryCoverReport.build(
        pdfTarget,
        current_entity_configuration,
        current_user_unity,
        current_user_classroom,
        '',
        current_teacher,
        current_user_school_year
      )

      ini = Time.now

      active_enrollment_classrooms = StudentEnrollmentClassroom.by_classroom(current_user_classroom.id).active
      school_calendar = SchoolCalendar.find_by(
          unity: current_unity.id,
          year: current_user_school_year
        )

      if teacher_allow_absence_by_discipline? || classroom_has_general_absence(current_user_classroom) == false
        aux_disciplines = @disciplines
        class_numbers_array = [1..5]
      else
        aux_disciplines = [@disciplines.first]
        class_numbers_array = []
      end

      aux_disciplines.each do |discipline|

        @attendance_record_report_form = AttendanceRecordReportForm.new(
          unity_id: current_unity.id,
          school_calendar_year: current_school_year,
          classroom_id: current_user_classroom.id,
          discipline_id: discipline.id,
          school_calendar: school_calendar,
          period: Periods::FULL,
          current_teacher_id: current_teacher.id,
          start_at: @diary_report_form.start_at,
          end_at: @diary_report_form.end_at,
          class_numbers: class_numbers_array
        )

        # if classroom_has_general_absence(current_user_classroom) == true
        #   @attendance_record_report_form.global_absence = true
        # else          
        # end
        
        if @attendance_record_report_form.valid?
          attendance_record_report = AttendanceRecordReportPortrait.build(
            current_entity_configuration,
            current_user_unity,
            current_teacher,
            current_user_school_year,
            @attendance_record_report_form.start_at,
            @attendance_record_report_form.end_at,
            @attendance_record_report_form.daily_frequencies,
            @attendance_record_report_form.enrollment_classrooms_list,
            [],
            @attendance_record_report_form.school_calendar,
            @attendance_record_report_form.second_teacher_signature,
            @attendance_record_report_form.students_frequencies_percentage,
            current_user,
            current_user_classroom.description
          )
          
          add_pdf_to_merge(pdfTarget, report_name('frequencia'), attendance_record_report.render)        
        else
          Rails.logger.error "Ocorreu um erro ao carregar frequência"        
        end
        finish = Time.now
        diff = finish - ini
        tempo_total += diff
        my_logger.info("Tempo de carregamento frequência #{diff}")
      end

      #contents
      ini = Time.now
      @disciplines.each do |discipline|
        
        continue_loop = true
        [ContentRecordReportTypes::CONTENT_RECORD, ContentRecordReportTypes::LESSON_PLAN].each do |report_type|
          
            if continue_loop == false
              break
            end
            @discipline_lesson_plan_report_form = DisciplineLessonPlanReportForm.new(
              teacher_id: current_teacher_id,
              unity_id: current_user_unity.id,
              classroom_id: current_user_classroom.id,
              discipline_id: discipline.id,
              date_start: @diary_report_form.start_at,
              date_end: @diary_report_form.end_at
            )

            @discipline_lesson_plan_report_form.author = PlansAuthors::ALL
            @discipline_lesson_plan_report_form.report_type = report_type

            if @discipline_lesson_plan_report_form.valid?

              if report_type == ContentRecordReportTypes::CONTENT_RECORD
                report = DisciplineContentRecordReport.build(current_entity_configuration,
                                                                      current_unity,
                                                                      @discipline_lesson_plan_report_form.date_start,
                                                                      @discipline_lesson_plan_report_form.date_end,
                                                                      @discipline_lesson_plan_report_form.discipline_content_record,
                                                                      current_teacher,
                                                                      current_user_classroom)                                                                      
                report_name = report_name('conteudo')
              else

                report = DisciplineLessonPlanReport.build(current_entity_configuration,
                                                                      current_unity,
                                                                      @discipline_lesson_plan_report_form.date_start,
                                                                      @discipline_lesson_plan_report_form.date_end,
                                                                      @discipline_lesson_plan_report_form.discipline_lesson_plan,
                                                                      current_teacher,
                                                                      current_user_classroom)                                                                      
                report_name = report_name('plano-de-aula')
              end
              
              add_pdf_to_merge(pdfTarget, report_name, report.render)
              continue_loop = false

            else
              Rails.logger.error "Ocorreu um erro ao carregar conteúdos da disciplina"  
              Rails.logger.error "#{@discipline_lesson_plan_report_form.inspect}"  
            end
        end
      end

      @knowledge_areas.each do |knowledge_area|

        continue_loop = true
        [ContentRecordReportTypes::CONTENT_RECORD, ContentRecordReportTypes::LESSON_PLAN].each do |report_type|
            if continue_loop == false
              break
            end

            @knowledge_area_lesson_plan_report_form = KnowledgeAreaLessonPlanReportForm.new(
              unity_id: current_unity.id,
              classroom_id: current_user_classroom.id,
              teacher_id: current_teacher_id,
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
                                                                                            current_teacher)      
                  report_name = report_name('conteudo')
              else
                  report = KnowledgeAreaLessonPlanReport.build(current_entity_configuration,
                                                                                            @knowledge_area_lesson_plan_report_form.date_start,
                                                                                            @knowledge_area_lesson_plan_report_form.date_end,
                                                                                            @knowledge_area_lesson_plan_report_form.knowledge_area_lesson_plan,
                                                                                            current_teacher)      
                  report_name = report_name('plano-de-aula')

              end
              add_pdf_to_merge(pdfTarget, report_name, report.render)

              continue_loop = false
            else
              Rails.logger.error "Ocorreu um erro ao carregar conteúdos da área de conhecimento: #{knowledge_area.description}"
              Rails.logger.error "#{@knowledge_area_lesson_plan_report_form.inspect}"  
            end
        end
      end

      finish = Time.now
      diff = finish - ini
      tempo_total += diff
      my_logger.info("Tempo de carregamento conteúdos #{diff}")



      ### avaliations
      ini = Time.now
      @disciplines.by_score_type(ScoreTypes::NUMERIC).each do |discipline|
        @avaliation_forms = []

        if @school_calendar_classroom_steps.any?
          @exam_average_report_form = ExamAverageReportForm.new(
            unity_id: current_user_unity.id,
            classroom_id: current_user_classroom.id,
            discipline_id: discipline.id,
            school_calendar_classroom_steps: @school_calendar_classroom_steps                        
          )
        else
          @exam_average_report_form = ExamAverageReportForm.new(
            unity_id: current_user_unity.id,
            classroom_id: current_user_classroom.id,
            discipline_id: discipline.id,
            school_calendar_steps: @school_calendar_steps
          )
        end

        @avaliation_forms << @exam_average_report_form

        @avaliation_forms.each do |avaliation_discipline|
          if avaliation_discipline.valid? 
            exam_record_report = @school_calendar_classroom_steps.any? ? build_by_classroom_steps(avaliation_discipline) : build_by_school_steps(avaliation_discipline)
            add_pdf_to_merge(pdfTarget, report_name('avaliacao'), exam_record_report.render)
          else
            Rails.logger.error "Ocorreu um erro ao carregar avaliações da disciplina"  
            Rails.logger.error "#{avaliation_discipline.inspect}"  
          end
        end
      end
      finish = Time.now
      diff = finish - ini
      tempo_total += diff
      my_logger.info("Tempo de carregamento avaliações numéricas #{diff}")

      ### avaliações conceituais
      ini = Time.now
      ConceptualExamReportBatchBuilder.new(
        entity_configuration: current_entity_configuration,
        unity: current_user_unity,
        classroom: current_user_classroom,
        teacher_id: current_teacher.id,
        start_at: @diary_report_form.start_at,
        end_at: @diary_report_form.end_at
      ).each_rendered_report do |render|
        add_pdf_to_merge(pdfTarget, report_name('avaliacao-conceitual'), render)
      end
      finish = Time.now
      diff = finish - ini
      tempo_total += diff
      my_logger.info("Tempo de carregamento avaliações conceituais #{diff}")

      # parecer
      if classroom_has_opinion_type(current_user_classroom) == true
        ini = Time.now
        @descriptive_form = DescriptiveReportForm.new(
          classroom_id: current_user_classroom.id,
          start_at: @diary_report_form.start_at,
          end_at: @diary_report_form.end_at
        )

        if @descriptive_form.valid?
          descriptive_report = DescriptiveReport.build(
            current_entity_configuration, 
            current_user_unity, 
            current_user_school_year, 
            @descriptive_form.fetch_exam_steps, 
            @descriptive_form.fetch_exam_values, 
            @descriptive_form.fetch_students,
            active_enrollment_classrooms,
            current_user_classroom,
            @descriptive_form.is_annual,
            true
          )
    
          add_pdf_to_merge(pdfTarget, report_name('parecer'), descriptive_report.render)
        end
        finish = Time.now
        diff = finish - ini
        tempo_total += diff
        my_logger.info("Tempo de carregamento de parecer descritivo #{diff}")
      end

      ini = Time.now

      filename_diary = report_name("diario#{current_user_school_year}-#{current_user_classroom.description}-#{current_teacher.name.split.first}", 4)
      
      filename_diary_full_path = merge_pdf(pdfTarget, filename_diary)

      if @diary_report_form.receive_email_confirmation_as_boolean == true
        send_mail("Chegou um novo diário", 
                  "Olá! Segue anexo o diário escolar do(a) professor(a) #{current_teacher.name}\nTurma: #{current_user_classroom.description}", 
                  filename_diary_full_path, 
                  current_user.email) 
      end

      redirect_to filename_diary

      finish = Time.now
      diff = finish - ini
      tempo_total += diff
      my_logger.info("Tempo de carregamento do PDF #{diff}")
      
      my_logger.info("TEMPO TOTAL: #{tempo_total}")
    end    
  
    private
  
    def resource_params
      params.require(:diary_report_form).permit(
        :unity_id,
        :classroom_id,
        :discipline_id,
        :knowledge_area_id,
        :start_at,
        :end_at,
        :teacher_id,
        :school_calendar_year,
        :receive_email_confirmation
      )
    end

    def build_by_school_steps(exam_average_report_form)
      @students_enrollments ||= exam_average_report_form.students_enrollments
      ExamStepAverageReport.build(
        current_entity_configuration,
        current_user_unity,
        current_teacher,
        current_school_year,
        current_user_classroom,
        Discipline.find(exam_average_report_form.discipline_id),
        exam_average_report_form.steps,
        @students_enrollments
      )
    end
  
    def build_by_classroom_steps(exam_average_report_form)
      @students_enrollments ||= exam_average_report_form.students_enrollments
      ExamStepAverageReport.build(
        current_entity_configuration,
        current_user_unity,
        current_teacher,
        current_school_year,
        current_user_classroom,
        Discipline.find(exam_average_report_form.discipline_id),
        exam_average_report_form.classroom_steps,
        @students_enrollments
      )
    end
  
    def set_options_by_user
      @unities = [current_user_unity]
  
      return fetch_linked_by_teacher

    end
  
    def fetch_linked_by_teacher
      @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(
        current_teacher.id,
        current_unity,
        current_school_year
      )
      @classrooms ||= @fetch_linked_by_teacher[:classrooms]
      @disciplines ||= @fetch_linked_by_teacher[:disciplines].by_classroom_id(
        current_user_classroom.id
      ).not_descriptor.not_grouper

      @knowledge_areas ||= KnowledgeArea.by_teacher(current_teacher.id)
                                      .by_classroom_id(current_user_classroom.id)
                                      .ordered

    end

    def set_school_calendars
      school_calendar = CurrentSchoolCalendarFetcher.new(
        Unity.find(current_user_unity.id),
        Classroom.find(current_user_classroom.id),
        current_school_year
      ).fetch
  
      @school_calendar_steps = SchoolCalendarStep.where(school_calendar: school_calendar).ordered
      @school_calendar_classroom_steps = SchoolCalendarClassroomStep.by_classroom(current_user_classroom.id).ordered
    end
  
end
  