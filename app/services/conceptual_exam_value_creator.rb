class ConceptualExamValueCreator
  def self.create_empty_by(classroom_id, teacher_id, grades_in_disciplines)
    new(classroom_id, teacher_id, grades_in_disciplines).create_empty
  end

  def initialize(classroom_id, teacher_id, grades_in_disciplines)
    raise ArgumentError if classroom_id.blank? || teacher_id.blank? || grades_in_disciplines.blank?

    @classroom_id = classroom_id
    @teacher_id = teacher_id
    @grades_in_disciplines = grades_in_disciplines
  end

  def create_empty
    @grades_in_disciplines.each do |grade, disciplines|
      next if grade.blank?

      conceptual_exam_values_to_create(grade).each do |record|
        student_enrollment_id = student_enrollment_id(record.student_id, classroom_id, record.recorded_at)

        next if student_enrollment_id.blank?
        next if exempted_discipline?(student_enrollment_id, record.discipline_id, record.step_number)
        next if ConceptualExamValue.find_by(conceptual_exam_id: record.conceptual_exam_id, discipline_id: record.discipline_id)
        next if disciplines.include?(record.discipline_id)

        begin
          ConceptualExamValue.create_with(
            value: nil,
            exempted_discipline: false
          ).find_or_create_by!(
            conceptual_exam_id: record.conceptual_exam_id,
            discipline_id: record.discipline_id
          )
        rescue ActiveRecord::RecordNotUnique
          retry
        end
      end
    end
  end

  private

  attr_accessor :teacher_id, :classroom_id, :grade_id

  def search_disciplines_related_to_grades(classroom_id, grade)
    classroom = Classroom.find(classroom_id)
    step_fetcher = StepsFetcher.new(classroom)
    school_calendar = step_fetcher.school_calendar

    SchoolCalendarDisciplineGrade.where(
      school_calendar_id: school_calendar.id,
      grade_id: grade
    ).pluck(:discipline_id)
  end


  def conceptual_exam_values_to_create(grade)
    disciplines = search_disciplines_related_to_grades(classroom_id, grade)

    TeacherDisciplineClassroom.joins(classroom: :conceptual_exams)
                              .joins(join_conceptual_exam_value)
                              .by_teacher_id(teacher_id)
                              .by_classroom(classroom_id)
                              .by_discipline_id(disciplines)
                              .where(conceptual_exams: { classroom_id: classroom_id })
                              .where(conceptual_exam_values: { id: nil })
                              .select(
                                <<-SQL
                                  conceptual_exams.id AS conceptual_exam_id,
                                  conceptual_exams.student_id AS student_id,
                                  conceptual_exams.recorded_at AS recorded_at,
                                  conceptual_exams.step_number AS step_number,
                                  teacher_discipline_classrooms.discipline_id AS discipline_id
                                SQL
                              )
  end

  def join_conceptual_exam_value
    <<-SQL
      LEFT JOIN conceptual_exam_values
             ON conceptual_exam_values.conceptual_exam_id = conceptual_exams.id
            AND conceptual_exam_values.discipline_id = teacher_discipline_classrooms.discipline_id
    SQL
  end

  def student_enrollment_id(student_id, classroom_id, recorded_at)
    StudentEnrollment.by_student(student_id)
                     .by_classroom(classroom_id)
                     .by_date(recorded_at)
                     .first
                     .try(:id)
  end

  def exempted_discipline?(student_enrollment_id, discipline_id, step_number)
    StudentEnrollmentExemptedDiscipline.by_student_enrollment(student_enrollment_id)
                                       .by_discipline(discipline_id)
                                       .by_step_number(step_number)
                                       .exists?
  end
end
