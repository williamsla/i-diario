module Api
  module V2
    class MonthlyAbsenceByStudentReportsController < Api::V2::BaseController
      def report
        @form = MonthlyAbsenceByStudentReportForm.new(report_params)

        if @form.valid?
          pdf_report = MonthlyAbsenceByStudentReport.build(current_entity_configuration, @form)

          send_data pdf_report.render,
                    filename: @form.filename,
                    type: 'application/pdf',
                    disposition: 'inline'
        else
          render json: { errors: @form.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def report_params
        {
          unity_api_code: params[:unity_api_code] || params[:cod_escola],
          year: params[:year] || params[:ano],
          months: params[:months] || params[:meses],
          grade_id: params[:grade_id] || params[:serie_id],
          classroom_id: params[:classroom_id] || params[:turma_id],
          sort_by: params[:sort_by] || params[:ordenar]
        }
      end
    end
  end
end
