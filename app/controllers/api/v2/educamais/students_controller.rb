# frozen_string_literal: true

module Api
  module V2
    module Educamais
      class StudentsController < BaseController
        def index
          classroom = Classroom.find(params[:classroom_id])
          ensure_unity_access!(classroom.unity_id)

          date = params[:date].presence ? Date.parse(params[:date].to_s) : Date.current

          # Lista da turma para o gabarito SAEB — sem filtro por disciplina do diário.
          enrollments = StudentEnrollment.by_classroom(classroom.id)
                                         .joins(:student)
                                         .includes(:student)
                                         .by_date(date)
                                         .active
                                         .ordered
                                         .to_a
                                         .uniq(&:student_id)

          render_educamais_json(
            enrollments.map { |enrollment|
              student = enrollment.student
              {
                id: student.id,
                name: student.to_s,
                api_code: student.api_code
              }
            }
          )
        end
      end
    end
  end
end
