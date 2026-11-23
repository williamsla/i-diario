# frozen_string_literal: true

class EducamaisLaunchController < ApplicationController
  def show
    authorize Educamais, :launch?

    base_url = EducaMais::Config.app_url
    return redirect_to root_path, alert: 'Educa+ não configurado.' if base_url.blank?

    if current_user.current_unity.blank?
      return redirect_to root_path,
        alert: 'Selecione uma escola no i-diário (barra superior) antes de abrir o Educa+.'
    end

    secret = EducaMais::Config.jwt_secret
    token = EducaMais::JwtToken.encode(
      EducaMais::LaunchPayload.build(current_user, request: request),
      secret: secret
    )
    redirect_to "#{base_url}/auth/callback?token=#{CGI.escape(token)}"
  end
end
