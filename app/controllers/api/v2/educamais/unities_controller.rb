# frozen_string_literal: true

module Api
  module V2
    module Educamais
      class UnitiesController < BaseController
        def index
          unities = scoped_unities.ordered

          render_educamais_json(
            unities.map { |u|
              { id: u.id, name: u.name, api_code: u.api_code }
            }
          )
        end
      end
    end
  end
end
