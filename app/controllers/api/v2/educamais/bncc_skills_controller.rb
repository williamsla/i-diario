# frozen_string_literal: true

module Api
  module V2
    module Educamais
      class BnccSkillsController < BaseController
        def index
          skills = EducaMais::BnccSkillsQuery.call(
            q: params[:q],
            serie: params[:serie],
            disciplina: params[:disciplina],
            limit: params[:limit]
          )

          render_educamais_json(
            skills.map { |skill|
              {
                id: skill.id,
                code: skill.code,
                description: skill.description
              }
            }
          )
        end
      end
    end
  end
end
