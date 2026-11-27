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
          today = enrollment_date
          classrooms = StudentEnrollmentClassroom.by_classroom(classroom_id)
                                                 .active
                                                 .includes(student_enrollment: :student)
                                                 .to_a
                                                 .select { |enrollment_classroom| enrolled_on?(enrollment_classroom, today) }

          classrooms
            .group_by { |enrollment_classroom| enrollment_classroom.student_enrollment&.student_id }
            .map { |_student_id, group|
              group.max_by { |enrollment_classroom|
                parse_enrollment_date(enrollment_classroom.joined_at) || Date.new(1, 1, 1)
              }
            }
            .compact
            .select { |enrollment_classroom| enrollment_classroom.student_enrollment&.student }
            .sort_by { |enrollment_classroom|
              [
                enrollment_classroom.sequence.to_i,
                enrollment_classroom.student_enrollment.student.to_s
              ]
            }
            .map(&:student_enrollment)
        end

        # joined_at e left_at são texto. by_date compara com a data de hoje como
        # texto e deixa de fora enturmação anterior ou posterior ao início do ano.
        def enrolled_on?(enrollment_classroom, date)
          joined_at = parse_enrollment_date(enrollment_classroom.joined_at)
          left_at = parse_enrollment_date(enrollment_classroom.left_at)
          return false if joined_at && joined_at > date
          return true if left_at.nil?

          left_at >= date
        end

        def parse_enrollment_date(value)
          return if value.blank?

          value.to_date
        rescue ArgumentError, TypeError
          nil
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
