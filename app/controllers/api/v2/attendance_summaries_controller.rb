module Api
  module V2
    class AttendanceSummariesController < Api::V2::BaseController
      def show
        summary = AttendanceSummaryByShift.new(
          cod_escola: params[:cod_escola] || params[:unity_api_code],
          data: params[:data] || params[:frequency_date],
          turno: params[:turno] || params[:period]
        ).call

        render json: summary
      rescue AttendanceSummaryByShift::Error => exception
        render json: { errors: exception.message }, status: :unprocessable_entity
      end

      private

      def authenticate_api!
        configuration = IeducarApiConfiguration.current
        header_token = request.headers['token'].to_s.strip
        candidates = [configuration.token, configuration.api_security_token].map { |value| value.to_s.strip }.reject(&:blank?)

        return if candidates.any? { |candidate| candidate.bytesize == header_token.bytesize && Devise.secure_compare(candidate, header_token) }

        render_invalid_token
      end
    end
  end
end
