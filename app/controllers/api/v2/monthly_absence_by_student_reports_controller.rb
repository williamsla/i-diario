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

      def authenticate_api!
        access_key = IeducarApiConfiguration.current.token.to_s.strip
        header_token = request.headers['token'].to_s.strip

        return if Devise.secure_compare(access_key, header_token)

        render_invalid_token
      end

      def report_params
        {
          unity_api_code: params[:unity_api_code] || params[:cod_escola],
          year: params[:year] || params[:ano],
          months: params[:months] || params[:meses],
          grade_id: params[:grade_id] || params[:serie_id],
          classroom_id: params[:classroom_id] || params[:turma_id],
          sort_by: params[:sort_by] || params[:ordenar],
          include_without_absences: params[:include_without_absences] || params[:exibir_sem_faltas]
        }
      end
    end
  end
end
