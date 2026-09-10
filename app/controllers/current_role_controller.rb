class CurrentRoleController < ApplicationController
  ALL_ROUTES = Rails.application.routes.routes.map { |route|
    if route.verb == /^GET$/ && route.defaults[:locale] == 'pt-BR'
      [route.defaults.values.join('#'), route.defaults]
    end
  }.compact.to_h.freeze

  def set
    current_role_form = CurrentRoleForm.new(resource_params)

    respond_to do |format|
      if current_role_form.save
        flash[:notice] = I18n.t('current_role.set.notice')
        format.json { render json: current_role_form }
      else
        format.json { render json: current_role_form.errors, status: :unprocessable_entity }
      end

      format.html do
        redirect_to_path(request.referer)
      end
    end
  end

  def available_classrooms
    profile = CurrentProfile.new(current_user, profile_filters(
      :by_unity_id, :by_school_year, :by_teacher_id, :by_user_role_id
    ))

    render json: { classrooms: profile.classrooms_as_json }
  end

  def available_disciplines
    profile = CurrentProfile.new(current_user, profile_filters(:by_classroom_id, :by_teacher_id))

    render json: { disciplines: profile.disciplines_as_json }
  end

  def available_school_years
    profile = CurrentProfile.new(current_user, profile_filters(:by_user_role_id, :by_unity_id))

    render json: { school_years: profile.school_years_as_json }
  end

  def available_teachers
    filters = profile_filters(:by_unity_id, :by_school_year, :by_classroom_id, :by_user_role_id)
    return render json: { teachers: [] } if filters[:by_classroom_id].blank?

    profile = CurrentProfile.new(current_user, filters)

    render json: { teachers: profile.teachers_as_json }
  end

  def available_unities
    profile = CurrentProfile.new(current_user, profile_filters(:by_unity_id, :by_user_role_id))

    render json: { unities: profile.unities_as_json }
  end

  def available_teacher_profiles
    profile = CurrentProfile.new(current_user, profile_filters(:by_unity_id, :by_school_year))

    render json: { teacher_profiles: profile.teacher_profiles_as_json }
  end

  private

  def profile_filters(*keys)
    raw = params[:filter]
    return {} if raw.blank?

    raw = ActionController::Parameters.new(raw) unless raw.is_a?(ActionController::Parameters)
    raw.permit(*keys).to_h
  end

  def resource_params
    params.require(:user).permit(
      :current_user_role_id, :current_unity_id, :current_classroom_id, :current_discipline_id, :current_teacher_id,
      :current_school_year, :current_knowledge_area_id
    ).merge(current_user: current_user)
  end

  def redirect_to_path(referer)
    ref_route = Rails.application.routes.recognize_path(referer)
    controller = ref_route[:controller]

    action = ALL_ROUTES["#{controller}#index#pt-BR"] ||
             ALL_ROUTES["#{controller}#new#pt-BR"] ||
             ALL_ROUTES["#{controller}#form#pt-BR"]

    redirect_to action || root_path
  rescue ActionController::RoutingError, ActionController::UrlGenerationError
    redirect_to root_path
  end
end
