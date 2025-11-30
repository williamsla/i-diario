# frozen_string_literal: true

class ReportGenerator
  def self.call(html, driver: :chrome)
    report_html_url = Rails.application.secrets.report_html_url
    report_html_secret_key = Rails.application.secrets.report_html_secret_key || 
                             Rails.application.secrets.resport_html_secret_key # Fallback para typo antigo
    
    raise ArgumentError, "report_html_url não configurado em secrets.yml" if report_html_url.blank?
    raise ArgumentError, "report_html_secret_key não configurado em secrets.yml" if report_html_secret_key.blank?
    
    RestClient.post(report_html_url, {
      html: html,
      driver: driver
    }, {
      Authorization: "Bearer #{report_html_secret_key}"
    })
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error "Erro ao gerar relatório: #{e.message}"
    Rails.logger.error "Response: #{e.response}" if e.response
    raise
  rescue StandardError => e
    Rails.logger.error "Erro inesperado ao gerar relatório: #{e.message}"
    raise
  end
end
