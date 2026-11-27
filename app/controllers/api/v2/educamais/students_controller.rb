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
          serialize_enrollments(classroom, enrollments_for(classroom.id, params[:grade_id]))
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

        # Mesma base da frequência: matrícula ativa na turma, inclusive com enturmação
        # anterior ao início do ano. A data mais recente não pode esconder a série
        # em que o aluno está hoje — a frequência escolhe a enturmação da data.
        def enrollments_for(classroom_id, grade_id = nil)
          StudentEnrollmentClassroom.by_classroom(classroom_id)
                                    .active
                                    .includes(student_enrollment: :student, classrooms_grade: :grade)
                                    .to_a
                                    .select { |enrollment_classroom| enrollment_classroom.student_enrollment&.student }
                                    .group_by { |enrollment_classroom| enrollment_classroom.student_enrollment.student_id }
                                    .map { |_student_id, group| pick_enrollment(group, grade_id) }
                                    .sort_by { |pick|
                                      student = pick[:enrollment].student_enrollment.student
                                      [pick[:enrollment].sequence.to_i, student.display_name.to_s, student.name.to_s]
                                    }
        end

        def pick_enrollment(group, grade_id)
          chosen = if grade_id.present?
                     same_grade = group.select { |enrollment_classroom|
                       enrollment_classroom.classrooms_grade&.grade_id.to_s == grade_id.to_s
                     }
                     same_grade.any? ? prefer_current(same_grade) : prefer_current(group)
                   else
                     prefer_current(group)
                   end
          listed = group.select { |enrollment_classroom| enrolled_on?(enrollment_classroom, Date.current) }
          listed = group if listed.empty?
          grades = listed.map { |enrollment_classroom|
            enrollment_classroom.classrooms_grade&.grade&.description.to_s.presence
          }.compact.uniq
          grade = chosen.classrooms_grade&.grade
          fallback_grades = [grade&.description.to_s].reject(&:blank?)
          {
            enrollment: chosen,
            grade_id: grade&.id,
            grade_description: grade&.description.to_s,
            grades: grades.presence || fallback_grades
          }
        end

        def prefer_current(group)
          today = Date.current
          current = group.select { |enrollment_classroom| enrolled_on?(enrollment_classroom, today) }
          pool = current.presence || group
          pool.max_by { |enrollment_classroom|
            [
              parse_enrollment_date(enrollment_classroom.joined_at) || Date.new(1, 1, 1),
              enrollment_classroom.sequence.to_i,
              enrollment_classroom.id.to_i
            ]
          }
        end

        # joined_at/left_at são texto. Data em branco ou ilegível não tira o aluno;
        # só sai quem entrou depois de hoje ou já deixou a turma.
        def enrolled_on?(enrollment_classroom, date)
          joined_at = parse_enrollment_date(enrollment_classroom.joined_at)
          left_at = parse_enrollment_date(enrollment_classroom.left_at)
          return false if joined_at && joined_at > date

          left_at.nil? || left_at >= date
        end

        def parse_enrollment_date(value)
          return if value.blank?

          text = value.to_s.strip
          return Date.iso8601(text) if text.match?(/\A\d{4}-\d{2}-\d{2}/)

          if (match = text.match(/\A(\d{1,2})\/(\d{1,2})\/(\d{4})/))
            return Date.new(match[3].to_i, match[2].to_i, match[1].to_i)
          end

          text.to_date
        rescue ArgumentError, TypeError
          nil
        end

        def serialize_enrollments(classroom, picks)
          picks.map do |pick|
            enrollment_classroom = pick[:enrollment]
            enrollment = enrollment_classroom.student_enrollment
            student = enrollment.student
            grade_name = pick[:grade_description].to_s
            grades = pick[:grades].presence || (grade_name.present? ? [grade_name] : classroom.grades.map(&:description))
            {
              id: student.id,
              name: student.display_name.presence || student.name.to_s,
              api_code: student.api_code,
              classroom_id: classroom.id,
              classroom: classroom.description,
              classroom_api_code: classroom.api_code,
              grade_id: pick[:grade_id],
              grade_description: grade_name,
              grade_descriptions: grades
            }
          end
        end
      end
    end
  end
end
