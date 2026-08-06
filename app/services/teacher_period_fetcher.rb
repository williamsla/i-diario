class TeacherPeriodFetcher
  def initialize(teacher_id, classroom_id, discipline_id)
    @teacher_id = teacher_id
    @classroom_id = classroom_id
    @discipline_id = discipline_id
  end

  def teacher_period
    return classroom_period if @teacher_id.blank?

    teacher_discipline_classrooms_scope.first.try(:period) || classroom_period
  end

  # Períodos distintos em que o professor atua na turma/disciplina (vínculo + quadro).
  def teacher_periods
    return [classroom_period] if @teacher_id.blank? || @classroom_id.blank?

    periods = periods_from_teacher_discipline_classrooms
    periods |= periods_from_lessons_boards if @discipline_id.present?
    periods = [classroom_period] if periods.blank?

    periods.map(&:to_i).reject(&:zero?).uniq.sort
  end

  def requires_period_selection?
    teacher_periods.size > 1
  end

  def classroom_period
    @classroom_period ||= Classroom.find(@classroom_id).period.to_i
  end

  private

  def teacher_discipline_classrooms_scope
    grade_ids = ClassroomsGrade.where(classroom_id: @classroom_id).map(&:grade)

    scope = TeacherDisciplineClassroom.where(
      teacher_id: @teacher_id,
      classroom_id: @classroom_id,
      grade_id: grade_ids
    )

    scope = scope.where(discipline_id: @discipline_id) if @discipline_id.present?
    scope
  end

  def periods_from_teacher_discipline_classrooms
    teacher_discipline_classrooms_scope.pluck(:period).compact
  end

  def periods_from_lessons_boards
    LessonsBoardLessonWeekday.includes(lessons_board_lesson: :lessons_board)
                             .by_classroom(@classroom_id)
                             .by_discipline(@discipline_id)
                             .by_teacher(@teacher_id)
                             .map { |allocation| allocation.lessons_board_lesson&.lessons_board&.period }
                             .compact
  end
end
