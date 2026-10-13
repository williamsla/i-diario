# frozen_string_literal: true

module Api
  module V2
    module Educamais
      class StudentsController < BaseController
        def index
          if params[:classroom_id].present?
            render_educamais_json(students_of_classroom(params[:classroom_id]))
          elsif params[:unity_id].present?
            render_educamais_json(students_of_unity(params[:unity_id]))
          else
            render json: { error: 'Informe classroom_id ou unity_id' }, status: :bad_request
          end
        end

        private

        def enrollment_date
          params[:date].presence ? Date.parse(params[:date].to_s) : Date.current
        end

        def students_of_classroom(classroom_id)
          classroom = Classroom.find(classroom_id)
          ensure_unity_access!(classroom.unity_id)
          serialize_enrollments(classroom, enrollments_for(classroom.id))
        end

        def students_of_unity(unity_id)
          ensure_unity_access!(unity_id)

          classrooms = Classroom.by_unity(unity_id)
                                .by_year(current_school_year)
                                .includes(:grades)
                                .ordered

          if current_user.teacher?
            teacher_id = current_user.teacher_id
            classrooms = classrooms.by_teacher_id(teacher_id) if teacher_id.present?
          end

          classrooms.distinct.flat_map do |classroom|
            serialize_enrollments(classroom, enrollments_for(classroom.id))
          end
        end

        def enrollments_for(classroom_id)
          StudentEnrollment.by_classroom(classroom_id)
                           .joins(:student)
                           .includes(:student)
                           .by_date(enrollment_date)
                           .active
                           .ordered
                           .to_a
                           .uniq(&:student_id)
        end

        def serialize_enrollments(classroom, enrollments)
          grades = classroom.grades.map(&:description)
          enrollments.map do |enrollment|
            student = enrollment.student
            {
              id: student.id,
              name: student.to_s,
              api_code: student.api_code,
              classroom_id: classroom.id,
              classroom: classroom.description,
              classroom_api_code: classroom.api_code,
              grade_descriptions: grades
            }
          end
        end
      end
    end
  end
end
