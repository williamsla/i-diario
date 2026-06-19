module LessonsBoardAvailability
  extend ActiveSupport::Concern

  private

  def parse_lessons_board_date(value)
    return nil if value.blank?
    return value.to_date if value.respond_to?(:to_date)
    return Date.parse(value) if value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    return Date.strptime(value.to_s, '%d/%m/%Y') if value.to_s.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z})

    nil
  rescue ArgumentError, TypeError
    nil
  end

  def weekday_name_for_date(date)
    I18n.t('date.day_names')[date.wday]
  end

  def lessons_board_date_message(key, date)
    t("daily_frequencies.new.#{key}", weekday: weekday_name_for_date(date), date: I18n.l(date))
  end

  def classroom_without_lessons_board?(classroom_id)
    !LessonsBoard.joins(:classrooms_grade)
                 .where(classrooms_grades: { classroom_id: classroom_id })
                 .exists?
  end

  def schedule_discipline_ids_for_classroom_weekday(classroom_id:, date:, period: nil)
    weekday = date.strftime('%A').downcase
    scope = LessonsBoardLessonWeekday.by_classroom(classroom_id).by_weekday(weekday)
    scope = scope.by_period(period) if period.present?
    scope.includes(:teacher_discipline_classroom)
         .map { |w| w.teacher_discipline_classroom.discipline_id }
         .uniq
  end

  def teacher_discipline_ids_on_schedule(classroom_id:, date:)
    weekday = date.strftime('%A').downcase
    LessonsBoardLessonWeekday
      .by_classroom(classroom_id)
      .by_teacher(current_teacher.id)
      .by_weekday(weekday)
      .includes(:teacher_discipline_classroom)
      .map { |w| w.teacher_discipline_classroom.discipline_id }
      .uniq
  end

  def build_disciplines_for_content_record_result(classroom:, record_date:)
    linked = TeacherClassroomAndDisciplineFetcher.fetch!(
      current_teacher.id,
      current_unity,
      current_school_year,
      classroom
    )
    all_disciplines = (linked[:disciplines] || []).select { |d| d.grouper == false && d.descriptor == false }
    all_disciplines = filter_disciplines_for_content_registration(all_disciplines, classroom)

    if all_disciplines.blank?
      return {
        disciplines: [],
        message: lessons_board_date_message(:no_linked_disciplines, record_date)
      }
    end

    return { disciplines: all_disciplines, message: nil } if classroom_without_lessons_board?(classroom.id)

    schedule_ids = schedule_discipline_ids_for_classroom_weekday(
      classroom_id: classroom.id,
      date: record_date,
      period: nil
    )
    if schedule_ids.blank?
      return {
        disciplines: [],
        message: lessons_board_date_message(:no_lessons_on_lessons_board_for_date, record_date)
      }
    end

    filtered = all_disciplines.select { |d| schedule_ids.include?(d.id) }
    if filtered.blank?
      return {
        disciplines: [],
        message: lessons_board_date_message(:no_disciplines_on_lessons_board_for_date, record_date)
      }
    end

    { disciplines: filtered, message: nil }
  end

  def knowledge_areas_for_classroom(classroom)
    if multigrade_infantil_fundamental_classroom?(classroom)
      infantil_discipline_ids = discipline_ids_for_grade_ids(
        classroom,
        infantil_grade_ids(classroom)
      )
      KnowledgeArea.by_teacher(current_teacher)
                   .by_discipline_id(infantil_discipline_ids)
                   .ordered
    else
      KnowledgeArea.by_teacher(current_teacher)
                   .by_classroom_id(classroom.id)
                   .ordered
    end
  end

  def build_knowledge_areas_for_content_record_result(classroom:, record_date:)
    knowledge_areas = filter_knowledge_areas_for_content_registration(
      knowledge_areas_for_classroom(classroom).includes(:disciplines),
      classroom
    )

    if knowledge_areas.blank?
      return {
        knowledge_areas: [],
        message: lessons_board_date_message(:no_linked_knowledge_areas, record_date)
      }
    end

    return { knowledge_areas: knowledge_areas, message: nil } if classroom_without_lessons_board?(classroom.id)

    teacher_discipline_ids = teacher_discipline_ids_on_schedule(
      classroom_id: classroom.id,
      date: record_date
    )

    if teacher_discipline_ids.blank?
      weekday = record_date.strftime('%A').downcase
      classroom_has_lessons = LessonsBoardLessonWeekday
                              .by_classroom(classroom.id)
                              .by_weekday(weekday)
                              .exists?
      message_key = if classroom_has_lessons
                      :no_teacher_lessons_on_lessons_board_for_date
                    else
                      :no_lessons_on_lessons_board_for_date
                    end

      return {
        knowledge_areas: [],
        message: lessons_board_date_message(message_key, record_date)
      }
    end

    filtered = knowledge_areas.select do |knowledge_area|
      knowledge_area.disciplines.any? { |discipline| teacher_discipline_ids.include?(discipline.id) }
    end

    if filtered.blank?
      return {
        knowledge_areas: [],
        message: lessons_board_date_message(:no_knowledge_areas_on_lessons_board_for_date, record_date)
      }
    end

    { knowledge_areas: filtered, message: nil }
  end
end
