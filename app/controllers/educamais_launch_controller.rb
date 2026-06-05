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
    token = EducaMais::JwtToken.encode(launch_payload, secret: secret)
    redirect_to "#{base_url}/auth/callback?token=#{CGI.escape(token)}"
  end

  private

  def launch_payload
    unity = current_user.current_unity

    {
      sub: current_user.id,
      entity_id: Entity.current.id,
      unity_id: unity&.id,
      classroom_id: current_user.current_classroom_id,
      school_year: current_user.current_school_year || Date.current.year,
      name: current_user.name,
      is_admin: current_user.admin? || current_user.administrator?,
      can_semed_view: semed_view_allowed?,
      exp: 2.hours.from_now.to_i
    }
  end

  def semed_view_allowed?
    current_user.admin? || current_user.administrator?
  end
end
