class DescriptiveReportController < ApplicationController
    
    before_action :require_current_classroom, only: [:form]
    before_action :require_current_teacher
  
    def form
      @steps = steps_fetcher.steps
      set_options_by_user

      @descriptive_report_form = DescriptiveReportForm.new(
        classroom_id: current_user_classroom.id,
        start_at: @steps.first.start_at,
        end_at: @steps.last.end_at
      )

    end
  
  
    def report
      
      @descriptive_report_form = DescriptiveReportForm.new(resource_params)
      
      if @descriptive_report_form.valid?
        descriptive_report = DescriptiveReport.build(
          current_entity_configuration, 
          current_user_unity, 
          current_user_school_year, 
          @descriptive_report_form.fetch_exam_values, 
          @descriptive_report_form.fetch_students, 
          current_user_classroom
        )
        
        send_pdf('parecer', descriptive_report.render)
      end
    end    
  
    private
  
    def resource_params
      params.require(:descriptive_report_form).permit(
        :classroom_id,
        :start_at,
        :end_at        
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
  
end
  