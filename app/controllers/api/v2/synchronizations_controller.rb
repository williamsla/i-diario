module Api
  module V2
    class SynchronizationsController < Api::V2::BaseController
      def create
        configuration = IeducarApiConfiguration.current

        unless configuration.persisted?
          render json: { errors: 'Configuração da API não encontrada' }, status: :unprocessable_entity
          return
        end

        synchronization = configuration.start_synchronization(author, current_entity&.id, false, true)

        render json: synchronization_payload(synchronization)
      rescue ActiveRecord::RecordNotUnique
        render json: synchronization_payload(IeducarApiSynchronization.started.first)
      rescue ActiveRecord::RecordInvalid => exception
        render json: { errors: exception.message }, status: :unprocessable_entity
      end

      def current
        synchronization = IeducarApiSynchronization.started.first
        synchronization ||= IeducarApiSynchronization.where(
          status: [ApiSynchronizationStatus::COMPLETED, ApiSynchronizationStatus::ERROR]
        ).order(:id).last

        render json: synchronization_payload(synchronization)
      end

      private

      def authenticate_api!
        configuration = IeducarApiConfiguration.current
        header_token = request.headers['token'].to_s.strip
        candidates = [configuration.token, configuration.api_security_token].map { |value| value.to_s.strip }.reject(&:blank?)

        return if candidates.any? { |candidate| candidate.bytesize == header_token.bytesize && Devise.secure_compare(candidate, header_token) }

        render_invalid_token
      end

      def author
        User.admin.first || User.first
      end

      def synchronization_payload(synchronization)
        {
          id: synchronization&.id,
          status: synchronization&.status,
          done_percentage: synchronization&.done_percentage,
          time_running: synchronization&.time_running,
          started_at: synchronization&.started_at&.iso8601,
          full_synchronization: synchronization&.full_synchronization || false
        }
      end
    end
  end
end
