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
      classroom.has_opinion_type?
    end
  
    def print_report
      set_options_by_user
      set_school_calendars
      ReportQueryCache.clear!

      my_logger = Logger.new("#{Rails.root}/log/my.log")
      my_logger.info("--------------------------------\nINICIANDO IMPRESSÃO DO DIÁRIO")
      tempo_total = 0

      @diary_report_form = DiaryReportForm.new(resource_params)

      current_user_classroom.classrooms_grades.includes(exam_rule: :differentiated_exam_rule, grade: :course).load

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

      active_enrollment_classrooms = StudentEnrollmentClassroom.by_classroom(current_user_classroom.id).active
      school_calendar = SchoolCalendar.find_by(
          unity: current_unity.id,
          year: current_user_school_year
        )

      if teacher_allow_absence_by_discipline? || classroom_has_general_absence(current_user_classroom) == false
        aux_disciplines = @disciplines
        class_numbers_array = (1..5).to_a
      else
        aux_disciplines = [@disciplines.first]
        class_numbers_array = []
      end

      aux_disciplines.each do |discipline|
        ini = Time.now

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

        if @attendance_record_report_form.valid?
          query_done = Time.now
          frequencies_percentage = if GeneralConfiguration.current.show_percentage_on_attendance_record_report
                                      @attendance_record_report_form.students_frequencies_percentage
                                    else
                                      {}
                                    end

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
            frequencies_percentage,
            current_user,
            current_user_classroom.description
          )
          
          add_pdf_to_merge(pdfTarget, report_name('frequencia'), attendance_record_report.render)
          my_logger.info("Tempo de frequência #{discipline.description}: consulta=#{query_done - ini} pdf=#{Time.now - query_done}")        
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
      evaluation_disciplines.each do |discipline|
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
            students = evaluation_students(discipline, avaliation_discipline)
            next if students.blank?

            exam_record_report = @school_calendar_classroom_steps.any? ? build_by_classroom_steps(avaliation_discipline, discipline, students) : build_by_school_steps(avaliation_discipline, discipline, students)
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
      my_logger.info("Tempo de carregamento avaliações #{diff}")

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
          students = @descriptive_form.fetch_students

          if students.any?
            descriptive_report = DescriptiveReport.build(
              current_entity_configuration, 
              current_user_unity, 
              current_user_school_year, 
              @descriptive_form.fetch_exam_steps, 
              @descriptive_form.fetch_exam_values, 
              students,
              active_enrollment_classrooms,
              current_user_classroom,
              @descriptive_form.is_annual,
              true
            )
      
            add_pdf_to_merge(pdfTarget, report_name('parecer'), descriptive_report.render)
          end
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
    ensure
      ReportQueryCache.clear!
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

    def build_by_school_steps(exam_average_report_form, discipline = nil, students = nil)
      ExamStepAverageReport.build(
        current_entity_configuration,
        current_user_unity,
        current_teacher,
        current_school_year,
        current_user_classroom,
        discipline || Discipline.find(exam_average_report_form.discipline_id),
        exam_average_report_form.steps,
        students || exam_average_report_form.students_enrollments
      )
    end
  
    def build_by_classroom_steps(exam_average_report_form, discipline = nil, students = nil)
      ExamStepAverageReport.build(
        current_entity_configuration,
        current_user_unity,
        current_teacher,
        current_school_year,
        current_user_classroom,
        discipline || Discipline.find(exam_average_report_form.discipline_id),
        exam_average_report_form.classroom_steps,
        students || exam_average_report_form.students_enrollments
      )
    end

    def evaluation_disciplines
      base = @disciplines.to_a
      base_ids = base.map(&:id)
      return [] if base_ids.blank?

      numeric_ids = Discipline.where(id: base_ids).by_score_type(ScoreTypes::NUMERIC).pluck('disciplines.id')
      selected_ids = numeric_ids | conceptual_evaluation_discipline_ids(base_ids)
      base.select { |discipline| selected_ids.include?(discipline.id) }
    end

    def conceptual_evaluation_discipline_ids(base_ids)
      classroom = current_user_classroom
      links = TeacherDisciplineClassroom.by_classroom(classroom.id)
                                       .by_teacher_id(current_teacher.id)
                                       .by_year(classroom.year)
                                       .to_a
      links = TeacherDisciplineClassroom.by_classroom(classroom.id).by_teacher_id(current_teacher.id).to_a if links.blank?

      grades = classroom.classrooms_grades.includes(exam_rule: :differentiated_exam_rule).to_a
      link_ids = links.select { |link|
        base_ids.include?(link.discipline_id) && conceptual_link_for_grade?(link, grades)
      }.map(&:discipline_id)

      valued_ids = ConceptualExamValue.joins(:conceptual_exam)
                                      .where(conceptual_exams: { classroom_id: classroom.id }, deleted_at: nil)
                                      .distinct
                                      .pluck(:discipline_id)

      (link_ids | (valued_ids & base_ids)).uniq
    end

    def conceptual_link_for_grade?(link, grades)
      grade = grades.find { |item| item.grade_id == link.grade_id }
      rules = [grade&.exam_rule, grade&.exam_rule&.differentiated_exam_rule].compact
      return link.score_type == ScoreTypes::CONCEPT if rules.blank?

      rules.any? { |rule|
        rule.score_type == ScoreTypes::CONCEPT ||
          (rule.score_type == ScoreTypes::NUMERIC_AND_CONCEPT && link.score_type == ScoreTypes::CONCEPT)
      }
    end

    def evaluation_students(discipline, form)
      @evaluation_students_by_discipline ||= {}
      return @evaluation_students_by_discipline[discipline.id] if @evaluation_students_by_discipline.key?(discipline.id)

      steps = form.classroom_steps.presence || form.steps
      list_params = {
        classroom: current_user_classroom.id,
        discipline: discipline.id,
        start_at: steps.first.start_at,
        end_at: steps.last.end_at,
        search_type: :by_date_range,
        show_inactive: false
      }

      numeric = StudentEnrollmentsList.new(
        list_params.merge(score_type: StudentEnrollmentScoreTypeFilters::NUMERIC)
      ).student_enrollments
      conceptual = StudentEnrollmentsList.new(
        list_params.merge(score_type: StudentEnrollmentScoreTypeFilters::CONCEPT)
      ).student_enrollments

      enrollments = (numeric + conceptual).uniq(&:id)
      @evaluation_students_by_discipline[discipline.id] = enrollments_for_discipline_grades(enrollments, discipline)
    end

    def enrollments_for_discipline_grades(enrollments, discipline)
      conceptual_student_ids = ConceptualExam.by_classroom(current_user_classroom.id)
                                            .joins(:conceptual_exam_values)
                                            .where(conceptual_exam_values: { discipline_id: discipline.id, deleted_at: nil })
                                            .pluck(:student_id)
      if conceptual_student_ids.present?
        with_concepts = StudentEnrollment.by_classroom(current_user_classroom.id)
                                         .where(student_id: conceptual_student_ids)
                                         .active
                                         .merge(StudentEnrollment.status_attending)
                                         .to_a
        enrollments = (enrollments + with_concepts).uniq(&:id)
      end

      return enrollments if enrollments.blank?

      grade_ids = TeacherDisciplineClassroom.by_classroom(current_user_classroom.id)
                                           .by_teacher_id(current_teacher.id)
                                           .by_discipline_id(discipline.id)
                                           .pluck(:grade_id)
                                           .compact
                                           .uniq
      return enrollments if grade_ids.blank?

      grades_by_student = ClassroomsGrade.by_classroom_id(current_user_classroom.id)
                                         .by_student_id(enrollments.map(&:student_id))
                                         .joins(:student_enrollments)
                                         .pluck('student_enrollments.student_id', :grade_id)
                                         .to_h

      enrollments.select { |enrollment|
        grade_ids.include?(grades_by_student[enrollment.student_id]) ||
          conceptual_student_ids.include?(enrollment.student_id)
      }
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
  