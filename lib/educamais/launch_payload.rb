# frozen_string_literal: true

module EducaMais
  module LaunchPayload
    module_function

    def build(user, request:, unity: nil)
      unity ||= user.current_unity
      {
        sub: user.id,
        entity_id: Entity.current.id,
        ibge_code: EntityConfiguration.current.ibge_code.presence,
        unity_id: unity&.id,
        classroom_id: classroom_id_for(user, unity),
        school_year: user.current_school_year || Date.current.year,
        name: user.name,
        is_admin: user.admin? || user.administrator?,
        can_semed_view: user.admin? || user.administrator?,
        idiario_api_url: EducaMais::Config.idiario_api_url(request: request),
        exp: 2.hours.from_now.to_i
      }.merge(EducaMais::UserClaims.role_payload(user))
    end

    def classroom_id_for(user, unity)
      classroom = user.current_classroom
      return if classroom.blank? || unity.blank?
      return if classroom.unity_id.to_i != unity.id

      classroom.id
    end
    private_class_method :classroom_id_for
  end
end
