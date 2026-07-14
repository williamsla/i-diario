class TutorialsController < ApplicationController
  before_action :authorize_tutorials_access!

  ALL_PROFILES = YAML.safe_load(
    File.read(Rails.root.join('config', 'tutorials.yml'))
  )['profiles'].freeze

  def index
    visible_keys = TutorialProfiles.visible_profiles(
      current_user,
      is_aee: is_aee,
      is_infantil: is_infantil && !is_aee
    )

    @profiles = visible_keys.each_with_object({}) do |key, hash|
      profile = ALL_PROFILES[key.to_s]
      hash[key.to_s] = profile if profile
    end
    @current_profile = TutorialProfiles.default_profile(
      current_user,
      is_aee: is_aee,
      is_infantil: is_infantil && !is_aee
    )
  end

  private

  def authorize_tutorials_access!
    authorize Tutorials, :index?
  end
end
