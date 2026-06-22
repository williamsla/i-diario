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

  def lessons_board_weekday_for_date(date)
    SchoolSaturdaysMapping.weekday_name_for(date, school_calendar: try(:current_school_calendar))
  end

  def saturday_school_day_without_equivalent_weekday?(classroom:, date:)
    SchoolSaturdaysMapping.saturday_school_day_without_equivalent_weekday?(
      date,
      classroom: classroom
    )
  end

  def schedule_discipline_ids_for_classroom_weekday(classroom_id:, date:, period: nil)
    weekday = lessons_board_weekday_for_date(date)
    scope = LessonsBoardLessonWeekday.by_classroom(classroom_id).by_weekday(weekday)
    scope = scope.by_period(period) if period.present?
    scope.includes(:teacher_discipline_classroom)
         .map { |w| w.teacher_discipline_classroom.discipline_id }
         .uniq
  end

  def linked_discipline_ids_on_schedule(classroom_id:, date:, discipline_ids:)
    return [] if discipline_ids.blank?

    board_discipline_ids = schedule_discipline_ids_for_classroom_weekday(
      classroom_id: classroom_id,
      date: date
    )

    board_discipline_ids & discipline_ids
  end

  def teacher_make_up_absences_on_date(classroom:, date:)
    TeacherAbsence
      .by_teacher(current_teacher.id)
      .with_make_up
      .where(make_up_date: date)
      .for_classroom_or_unity(classroom.id, classroom.unity_id)
  end

  def teacher_has_make_up_on_date?(classroom:, date:)
    teacher_make_up_absences_on_date(classroom: classroom, date: date).exists?
  end

  def disciplines_for_make_up_date(disciplines, classroom, date)
    absences = teacher_make_up_absences_on_date(classroom: classroom, date: date).to_a
    return [] if absences.blank?

    specific_discipline_ids = absences.map(&:discipline_id).compact.uniq
    if specific_discipline_ids.present?
      disciplines.select { |discipline| specific_discipline_ids.include?(discipline.id) }
    else
      disciplines
    end
  end

  def knowledge_areas_for_make_up_date(knowledge_areas, classroom, date)
    absences = teacher_make_up_absences_on_date(classroom: classroom, date: date).to_a
    return [] if absences.blank?

    specific_discipline_ids = absences.map(&:discipline_id).compact.uniq
    if specific_discipline_ids.present?
      knowledge_areas.select do |knowledge_area|
        knowledge_area.disciplines.any? { |discipline| specific_discipline_ids.include?(discipline.id) }
      end
    else
      knowledge_areas
    end
  end

  def schedule_unavailable_message(classroom:, date:, schedule_ids:)
    weekday = lessons_board_weekday_for_date(date)
    classroom_has_lessons = LessonsBoardLessonWeekday
                            .by_classroom(classroom.id)
                            .by_weekday(weekday)
                            .exists?

    message_key = if schedule_ids.blank?
                    classroom_has_lessons ? :no_teacher_lessons_on_lessons_board_for_date : :no_lessons_on_lessons_board_for_date
                  else
                    :no_disciplines_on_lessons_board_for_date
                  end

    lessons_board_date_message(message_key, date)
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
    return { disciplines: all_disciplines, message: nil } if saturday_school_day_without_equivalent_weekday?(
      classroom: classroom,
      date: record_date
    )

    schedule_ids = linked_discipline_ids_on_schedule(
      classroom_id: classroom.id,
      date: record_date,
      discipline_ids: all_disciplines.map(&:id)
    )

    if schedule_ids.present?
      filtered = all_disciplines.select { |d| schedule_ids.include?(d.id) }
      return { disciplines: filtered, message: nil } if filtered.present?
    end

    make_up_disciplines = disciplines_for_make_up_date(all_disciplines, classroom, record_date)
    if make_up_disciplines.present?
      return { disciplines: make_up_disciplines, message: nil }
    end

    {
      disciplines: [],
      message: schedule_unavailable_message(
        classroom: classroom,
        date: record_date,
        schedule_ids: schedule_ids
      )
    }
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
    return { knowledge_areas: knowledge_areas, message: nil } if saturday_school_day_without_equivalent_weekday?(
      classroom: classroom,
      date: record_date
    )

    linked_discipline_ids = knowledge_areas.flat_map { |knowledge_area| knowledge_area.disciplines.map(&:id) }.uniq
    scheduled_discipline_ids = linked_discipline_ids_on_schedule(
      classroom_id: classroom.id,
      date: record_date,
      discipline_ids: linked_discipline_ids
    )

    if scheduled_discipline_ids.present?
      filtered = knowledge_areas.select do |knowledge_area|
        knowledge_area.disciplines.any? { |discipline| scheduled_discipline_ids.include?(discipline.id) }
      end
      return { knowledge_areas: filtered, message: nil } if filtered.present?
    end

    make_up_knowledge_areas = knowledge_areas_for_make_up_date(knowledge_areas, classroom, record_date)
    if make_up_knowledge_areas.present?
      return { knowledge_areas: make_up_knowledge_areas, message: nil }
    end

    {
      knowledge_areas: [],
      message: schedule_unavailable_message(
        classroom: classroom,
        date: record_date,
        schedule_ids: scheduled_discipline_ids
      )
    }
  end
end
