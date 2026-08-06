# frozen_string_literal: true

module Api
  module V2
    module Educamais
      class ClassroomsController < BaseController
        def index
          unity_id = params[:unity_id].presence || jwt_claims[:unity_id]
          ensure_unity_access!(unity_id)

          classrooms = Classroom.by_unity(unity_id)
                                .by_year(current_school_year)
                                .ordered

          if params[:grade_id].present?
            classrooms = classrooms.by_grade(params[:grade_id])
          end

          if current_user.teacher?
            teacher_id = current_user.teacher_id
            classrooms = classrooms.by_teacher_id(teacher_id) if teacher_id.present?
          end

          render_educamais_json(
            classrooms.distinct.map { |c|
              {
                id: c.id,
                description: c.description,
                api_code: c.api_code,
                unity_id: c.unity_id,
                grade_descriptions: c.grades.pluck(:description)
              }
            }
          )
        end
      end
    end
  end
end
