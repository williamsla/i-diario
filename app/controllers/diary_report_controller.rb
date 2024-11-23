class DiaryReportController < ApplicationController
    DISCIPLINE_LESSON_PLAN_REPORT = "1"
    DISCIPLINE_CONTENT_RECORD = "2"
  
    before_action :require_current_classroom, only: [:form, :lesson_plan_report, :content_record_report]
    before_action :require_current_teacher
  
    def form
      Rails.logger.info "\n\n\n\n--- form teste----\n\n\n\n\n"
      Rails.logger.info "\n\n\n\n chamando print"
      @steps = steps_fetcher.steps

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

      @discipline_lesson_plan_report_form = DisciplineLessonPlanReportForm.new(
        teacher_id: current_teacher_id,
        unity_id: current_user_unity.id,
        classroom_id: current_user_classroom.id,
        discipline_id: current_user_discipline.id,
        date_start: @steps.first.start_at,
        date_end: @steps.last.end_at
      )

      @discipline_lesson_plan_report_form.author = PlansAuthors::ALL
      @discipline_lesson_plan_report_form.report_type = DISCIPLINE_CONTENT_RECORD
      
      Rails.logger.info "#{@discipline_lesson_plan_report_form.inspect}"

      print_report()
      
      Rails.logger.info "finalizou print"

    end
  
  
    def print_report
      
      pdfTarget = HexaPDF::Document.new     
      
      if @attendance_record_report_form.valid?
        attendance_record_report = AttendanceRecordReport.build(
          current_entity_configuration,
          current_teacher,
          current_user_school_year,
          @attendance_record_report_form.start_at,
          @attendance_record_report_form.end_at,
          @attendance_record_report_form.daily_frequencies,
          @attendance_record_report_form.enrollment_classrooms_list,
          @attendance_record_report_form.school_calendar_events,
          @attendance_record_report_form.school_calendar,
          @attendance_record_report_form.second_teacher_signature,
          @attendance_record_report_form.students_frequencies_percentage,
          current_user,
          current_user_classroom.id #resource_params[:classroom_id]
        )
        
        add_pdf_to_merge(pdfTarget, report_name('frequencia'), attendance_record_report.render)
        
      else
        Rails.logger.info "entrou no else 1"
        @attendance_record_report_form.school_calendar_year = current_school_year

        set_options_by_user
        fetch_collections
        
        # render :form
      end


      # @discipline_lesson_plan_report_form = DisciplineLessonPlanReportForm.new(resource_params)
      
      if @discipline_lesson_plan_report_form.valid?
        lesson_plan_report = DisciplineContentRecordReport.build(current_entity_configuration,
                                                                 @discipline_lesson_plan_report_form.date_start,
                                                                 @discipline_lesson_plan_report_form.date_end,
                                                                 @discipline_lesson_plan_report_form.discipline_content_record,
                                                                 current_teacher)
                                                                 
        add_pdf_to_merge(pdfTarget, report_name('conteudo'), lesson_plan_report.render)
        
      else
        Rails.logger.info "entrou no else 2"
        @discipline_lesson_plan_report_form
        set_options_by_user
      end

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
    end
  
    def set_options_by_user
      @admin_or_teacher ||= current_user.current_role_is_admin_or_employee?
      @unities ||= @admin_or_teacher ? Unity.ordered : [current_user_unity]
  
      return fetch_linked_by_teacher unless @admin_or_teacher
  
      fetch_collections
    end
  
    def fetch_linked_by_teacher
      @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(
        current_teacher.id,
        current_unity,
        current_school_year
      )
      @classrooms ||= @fetch_linked_by_teacher[:classrooms]
      @disciplines ||= @fetch_linked_by_teacher[:disciplines].by_classroom_id(
        @discipline_lesson_plan_report_form.classroom_id
      ).not_descriptor
    end
  
    def fetch_collections
      @number_of_classes = current_school_calendar.number_of_classes
      @classrooms ||= Classroom.by_unity(current_unity.id)
                               .by_year(current_user_school_year || Date.current.year)
                               .ordered
      @disciplines ||= Discipline.by_classroom_id(current_user_classroom.id)
                                 .not_descriptor
    end
  end
  