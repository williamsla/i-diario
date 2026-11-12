module IeducarApi
  class StudentAverages < Base
    # A consulta de nota é uma requisição por matrícula/disciplina/etapa.
    # Um relatório de turma estoura o limite da API (HTTP 429) se sair em rajada.
    THROTTLE = Mutex.new
    BASE_INTERVAL = 0.5
    MAX_INTERVAL = 2.0
    MAX_ATTEMPTS = 4
    CACHE_TTL = 10.minutes

    class << self
      def next_request_at
        @next_request_at ||= Time.at(0)
      end

      def next_request_at=(value)
        @next_request_at = value
      end

      def interval
        @interval ||= BASE_INTERVAL
      end

      def interval=(value)
        @interval = value
      end

      def reset_throttle!
        @next_request_at = Time.at(0)
        @interval = BASE_INTERVAL
      end
    end

    def fetch(params = {})
      registration_id = params[:registration_id]
      discipline_id = params[:discipline_id]
      stage = params[:stage]

      raise ApiError, 'É necessário informar o registration_id' if registration_id.blank?
      raise ApiError, 'É necessário informar o discipline_id' if discipline_id.blank?
      raise ApiError, 'É necessário informar o stage (etapa)' if stage.blank?

      cache_key = score_cache_key(registration_id, discipline_id, stage)
      cached = Rails.cache.read(cache_key)
      return cached unless cached.nil?

      endpoint = "#{url}/api/student-score"
      query_params = {
        access_key: access_key,
        secret_key: secret_key,
        registration_id: registration_id,
        discipline_id: discipline_id,
        stage: stage
      }
      request_url = "#{endpoint}?#{query_params.to_query}"

      log_request(endpoint, registration_id, discipline_id, stage)

      result = request_score(endpoint, request_url)
      Rails.cache.write(cache_key, result, expires_in: CACHE_TTL)
      result
    end

    private

    def log_request(endpoint, registration_id, discipline_id, stage)
      message = "GET #{endpoint} registration_id=#{registration_id} discipline_id=#{discipline_id} stage=#{stage}"
      Rails.logger.info(message)
      Sidekiq.logger.info(message)
    end

    def score_cache_key(registration_id, discipline_id, stage)
      [
        'ieducar-student-score',
        Entity.current&.id,
        url,
        registration_id.to_s,
        discipline_id.to_s,
        stage.to_s
      ]
    end

    def request_score(endpoint, request_url)
      attempt = 0

      begin
        attempt += 1
        wait_turn
        response = RestClient::Request.execute(
          method: :get,
          url: request_url,
          read_timeout: 240,
          open_timeout: 30
        )

        JSON.parse(response)
      rescue SocketError, RestClient::ExceptionWithResponse => error
        if RETRY_NETWORK_ERRORS.any? { |network_error| error.message.to_s.include?(network_error) }
          raise NetworkException, error.message
        end

        if rate_limited?(error) && attempt < MAX_ATTEMPTS
          delay = retry_delay(error, attempt)
          Rails.logger.warn(
            "API i-Educar limitou consultas de nota (HTTP 429) em #{endpoint}. " \
            "Nova tentativa #{attempt} de #{MAX_ATTEMPTS - 1} em #{delay}s."
          )
          postpone_requests(delay)
          retry
        end

        raise api_error(endpoint, error)
      rescue StandardError => error
        Rails.logger.error "Erro inesperado ao buscar média do i-educar: #{error.message}"
        raise ApiError, error.message
      end
    end

    def rate_limited?(error)
      error.respond_to?(:http_code) && error.http_code.to_i == 429
    end

    def retry_delay(error, attempt)
      header = retry_after_seconds(error)
      return [[header, 30].min, 1].max if header

      [2**attempt, 8].min
    end

    def retry_after_seconds(error)
      return unless error.respond_to?(:response) && error.response.respond_to?(:headers)

      headers = error.response.headers || {}
      raw = headers[:retry_after] || headers['retry_after'] || headers['Retry-After']
      return if raw.blank?

      seconds = raw.to_i
      seconds.positive? ? seconds : nil
    end

    def wait_turn
      THROTTLE.synchronize do
        delay = self.class.next_request_at - Time.current
        sleep(delay) if delay.positive?
        self.class.next_request_at = Time.current + self.class.interval
      end
    end

    def postpone_requests(delay)
      THROTTLE.synchronize do
        self.class.interval = [self.class.interval * 2, MAX_INTERVAL].min
        postponed = Time.current + delay
        self.class.next_request_at = postponed if postponed > self.class.next_request_at
      end
    end

    def api_error(endpoint, error)
      http_code = error.respond_to?(:http_code) ? error.http_code : 'N/A'
      error_class_name = error.class.name.split('::').last

      Rails.logger.error(
        "Erro ao acessar API i-Educar - URL: #{url}, Endpoint: #{endpoint}, " \
        "Erro: #{error_class_name}, HTTP: #{http_code}"
      )

      message = if http_code == 401
                  'Autenticação falhou (HTTP 401). Verifique se access_key e secret_key estão corretos.'
                elsif http_code == 404
                  "Endpoint não encontrado na API do i-Educar. Endpoint: #{endpoint}. Verifique se o recurso está disponível nesta versão da API."
                elsif http_code.to_i == 429
                  'A API do i-Educar limitou o número de consultas de nota (HTTP 429). Aguarde alguns instantes e tente novamente.'
                else
                  text = "Erro ao acessar API do i-Educar. URL: #{url}, Erro: #{error_class_name}"
                  text += " (HTTP #{http_code})" if http_code != 'N/A'
                  text += " - #{error.message}" if error.message.present?
                  text
                end

      ApiError.new(message)
    end
  end
end
