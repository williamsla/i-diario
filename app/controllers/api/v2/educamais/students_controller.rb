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

        # Matrícula ativa na turma, mesmo com enturmação anterior ao início do ano.
        # by_date compara joined_at/left_at como texto e tira essa data.
        def enrollments_for(classroom_id)
          StudentEnrollmentClassroom.by_classroom(classroom_id)
                                    .active
                                    .includes(student_enrollment: :student, classrooms_grade: :grade)
                                    .to_a
                                    .select { |enrollment_classroom| enrollment_classroom.student_enrollment&.student }
                                    .group_by { |enrollment_classroom| enrollment_classroom.student_enrollment.student_id }
                                    .map { |_student_id, group|
                                      group.max_by { |enrollment_classroom|
                                        [
                                          parse_enrollment_date(enrollment_classroom.joined_at) || Date.new(1, 1, 1),
                                          enrollment_classroom.index.to_i,
                                          enrollment_classroom.id.to_i
                                        ]
                                      }
                                    }
                                    .sort_by { |enrollment_classroom|
                                      [
                                        enrollment_classroom.sequence.to_i,
                                        enrollment_classroom.student_enrollment.student.to_s
                                      ]
                                    }
        end

        def parse_enrollment_date(value)
          return if value.blank?

          value.to_date
        rescue ArgumentError, TypeError
          nil
        end

        def serialize_enrollments(classroom, enrollment_classrooms)
          enrollment_classrooms.map do |enrollment_classroom|
            enrollment = enrollment_classroom.student_enrollment
            student = enrollment.student
            grade_name = enrollment_classroom.classrooms_grade&.grade&.description.to_s
            grades = grade_name.present? ? [grade_name] : classroom.grades.map(&:description)
            {
              id: student.id,
              name: student.to_s,
              api_code: student.api_code,
              classroom_id: classroom.id,
              classroom: classroom.description,
              classroom_api_code: classroom.api_code,
              grade_id: enrollment_classroom.classrooms_grade&.grade_id,
              grade_description: grade_name,
              grade_descriptions: grades
            }
          end
        end
      end
    end
  end
end
