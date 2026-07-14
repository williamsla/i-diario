class TutorialsPolicy < ApplicationPolicy
  def index?
    TutorialProfiles.allowed?(user)
  end
end
