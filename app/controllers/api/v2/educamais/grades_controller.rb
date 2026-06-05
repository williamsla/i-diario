# frozen_string_literal: true

module Api
  module V2
    module Educamais
      class GradesController < BaseController
        def index
          unity_id = params[:unity_id].presence || jwt_claims[:unity_id]
          ensure_unity_access!(unity_id)

          grades = Grade.by_unity(unity_id).by_year(current_school_year).ordered.distinct

          render_educamais_json(
            grades.map { |g|
              { id: g.id, description: g.description, api_code: g.api_code }
            }
          )
        end
      end
    end
  end
end
