class DiaryReportController < ApplicationController
    DISCIPLINE_LESSON_PLAN_REPORT = "1"
    DISCIPLINE_CONTENT_RECORD = "2"
  
    before_action :require_current_classroom, only: [:form, :lesson_plan_report, :content_record_report]
    before_action :require_current_teacher
  
    def form
      @steps = steps_fetcher.steps
      set_options_by_user
      set_school_calendars

      @attendance_record_report_form = AttendanceRecordReportForm.new(
        unity_id: current_unity.id,
        school_calendar_year: current_school_year,
        classroom_id: current_user_classroom.id,
        discipline_id: current_user_discipline.id,
        period: Periods::FULL,
        current_teacher_id: current_teacher.id,
        class_numbers: '', # get all class_numbers
        # global_absence: true
      )

      @attendance_record_report_form.start_at = @steps.first.start_at
      @attendance_record_report_form.end_at = @steps.last.end_at

      @attendance_record_report_form.school_calendar = SchoolCalendar.find_by(
        unity: @attendance_record_report_form.unity_id,
        year: current_user_school_year
      )

      @content_forms = []
      @avaliation_forms = []

      @disciplines.each do |discipline|
        #content
        @discipline_lesson_plan_report_form = DisciplineLessonPlanReportForm.new(
          teacher_id: current_teacher_id,
          unity_id: current_user_unity.id,
          classroom_id: current_user_classroom.id,
          discipline_id: discipline.id,
          date_start: @steps.first.start_at,
          date_end: @steps.last.end_at
        )

        @discipline_lesson_plan_report_form.author = PlansAuthors::ALL
        @discipline_lesson_plan_report_form.report_type = DISCIPLINE_CONTENT_RECORD

        @content_forms << @discipline_lesson_plan_report_form

        #avaliations
        # @school_calendar_steps.each do |step|
        #   @exam_record_report_form = ExamRecordReportForm.new(
        #     unity_id: current_user_unity.id,
        #     classroom_id: current_user_classroom.id,
        #     discipline_id: discipline.id,
        #     school_calendar_step_id: step.id
        #   )

        #   @avaliation_forms << @exam_record_report_form
        # end
        
        # @school_calendar_classroom_steps.each do |step|
        #   @exam_record_report_form = ExamRecordReportForm.new(
        #     unity_id: current_user_unity.id,
        #     classroom_id: current_user_classroom.id,
        #     discipline_id: discipline.id,
        #     school_calendar_classroom_step_id: step.id
        #   )

        #   @avaliation_forms << @exam_record_report_form
        # end

      end
      
      print_report()
      
    end
  
  
    def print_report
      
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

      descriptive_report = DescriptiveReport.build(
        current_entity_configuration, 
        current_user_unity, 
        current_user_school_year, 
        '1', 
        [], 
        current_user_classroom
      )
      add_pdf_to_merge(pdfTarget, report_name('parecer'), descriptive_report.render)

      # if @attendance_record_report_form.valid?
      #   attendance_record_report = AttendanceRecordReport.build(
      #     current_entity_configuration,
      #     current_user_unity,
      #     current_teacher,
      #     current_user_school_year,
      #     @attendance_record_report_form.start_at,
      #     @attendance_record_report_form.end_at,
      #     @attendance_record_report_form.daily_frequencies,
      #     @attendance_record_report_form.enrollment_classrooms_list,
      #     [],
      #     @attendance_record_report_form.school_calendar,
      #     @attendance_record_report_form.second_teacher_signature,
      #     @attendance_record_report_form.students_frequencies_percentage,
      #     current_user,
      #     current_user_classroom.description
      #   )
        
      #   add_pdf_to_merge(pdfTarget, report_name('frequencia'), attendance_record_report.render)
        
      # else
      #   Rails.logger.error "Ocorreu um erro ao carregar frequência"        
      #   # return
      # end

      
      # @content_forms.each do |content_discipline|
      #   if content_discipline.valid?
      #     lesson_plan_report = DisciplineContentRecordReport.build(current_entity_configuration,
      #                                                           current_unity,
      #                                                           content_discipline.date_start,
      #                                                           content_discipline.date_end,
      #                                                           content_discipline.discipline_content_record,
      #                                                           current_teacher,
      #                                                           current_user_classroom)
                                                                
      #     add_pdf_to_merge(pdfTarget, report_name('conteudo'), lesson_plan_report.render)
          
      #   else
      #     Rails.logger.error "Ocorreu um erro ao carregar conteúdos da disciplina"  
      #     Rails.logger.error "#{content_discipline.inspect}"  
      #     # return        
      #   end
      # end

      # ---------------------------------------------------
      
      # @avaliation_forms.each do |avaliation_discipline|
      #   if avaliation_discipline.valid?
      #     exam_record_report = @school_calendar_classroom_steps.any? ? build_by_classroom_steps(avaliation_discipline) : build_by_school_steps(avaliation_discipline)
      #     add_pdf_to_merge(pdfTarget, report_name('avaliacao'), exam_record_report.render)
      #   else
      #     Rails.logger.error "Ocorreu um erro ao carregar avaliações da disciplina"  
      #     Rails.logger.error "#{avaliation_discipline.inspect}"  
      #   end
      # end

      merge_pdf(pdfTarget, report_name('diario'))
    end
    
  
    private
  
    def resource_params
      params.require(:discipline_lesson_plan_report_form).permit(
        :unity_id,
        :classroom_id,
        :discipline_id,
        :date_start,
        :date_end,
        :author,
        :report_type,
        :teacher_id
      )
                
      params.require(:attendance_record_report_form).permit(:unity_id,
                                                            :classroom_id,
                                                            :period,
                                                            :discipline_id,
                                                            :class_numbers,
                                                            :start_at,
                                                            :end_at,
                                                            :school_calendar_year,
                                                            :current_teacher_id,
                                                            :second_teacher_signature,
                                                            :global_absence)
      
      params.require(:exam_record_report_form).permit(:unity_id,
                                                    :classroom_id,
                                                    :discipline_id,
                                                    :school_calendar_step_id,
                                                    :school_calendar_classroom_step_id)
    end

    def build_by_school_steps(exam_record_report_form)
      ExamRecordReport.build(
        current_entity_configuration,
        current_teacher,
        current_school_year,
        exam_record_report_form.step,
        current_test_setting_step(exam_record_report_form.step),
        exam_record_report_form.daily_notes,
        exam_record_report_form.students_enrollments,
        [],
        exam_record_report_form.school_term_recoveries,
        [],
        []
      )
    end
  
    def build_by_classroom_steps(exam_record_report_form)
      ExamRecordReport.build(
        current_entity_configuration,
        current_teacher,
        current_school_calendar.year,
        exam_record_report_form.classroom_step,
        current_test_setting_step(exam_record_report_form.classroom_step),
        exam_record_report_form.daily_notes_classroom_steps,
        exam_record_report_form.students_enrollments,
        [],
        exam_record_report_form.school_term_recoveries,
        [],
        []
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
      ).not_descriptor
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
  