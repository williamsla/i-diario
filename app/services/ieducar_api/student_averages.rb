module IeducarApi
  class StudentAverages < Base
    def fetch(params = {})
      # Parâmetros esperados pela nova API
      registration_id = params[:registration_id]
      discipline_id = params[:discipline_id]
      stage = params[:stage]

      raise ApiError, 'É necessário informar o registration_id' if registration_id.blank?
      raise ApiError, 'É necessário informar o discipline_id' if discipline_id.blank?
      raise ApiError, 'É necessário informar o stage (etapa)' if stage.blank?

      endpoint = "#{url}/api/student-score"
      query_params = {
        access_key: access_key,
        secret_key: secret_key,
        registration_id: registration_id,
        discipline_id: discipline_id,
        stage: stage
      }

      request_url = "#{endpoint}?#{query_params.to_query}"
      
      Rails.logger.info "GET #{request_url}"
      Sidekiq.logger.info "GET #{request_url}"
      
      begin
        response = RestClient::Request.execute(
          method: :get,
          url: request_url,
          read_timeout: 240,
          open_timeout: 30
        )

        JSON.parse(response)
      rescue SocketError, RestClient::ExceptionWithResponse => error
        if RETRY_NETWORK_ERRORS.any? { |network_error| error.message.include?(network_error) }
          raise NetworkException, error.message
        end

        http_code = error.respond_to?(:http_code) ? error.http_code : 'N/A'
        error_class_name = error.class.name.split('::').last

        Rails.logger.error "Erro ao acessar API i-Educar - URL: #{url}, Endpoint: #{endpoint}, URL Completa: #{request_url}, Erro: #{error_class_name}, HTTP: #{http_code}, Mensagem: #{error.message}"

        if http_code == 401
          error_message = "Autenticação falhou (HTTP 401). Verifique se access_key e secret_key estão corretos."
        elsif http_code == 404
          error_message = "Endpoint não encontrado na API do i-Educar. Endpoint: #{endpoint}. Verifique se o recurso está disponível nesta versão da API."
        else
          error_message = "Erro ao acessar API do i-Educar. URL: #{url}, Erro: #{error_class_name}"
          error_message += " (HTTP #{http_code})" if http_code != 'N/A'
          error_message += " - #{error.message}" if error.message.present?
        end
        raise ApiError, error_message
      rescue StandardError => error
        Rails.logger.error "Erro inesperado ao buscar média do i-educar: #{error.message}"
        raise ApiError, error.message
      end
    end
  end
end

