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
      classroom: classroom,
      school_calendar: try(:current_school_calendar)
    )
  end

  def infantil_classroom?(classroom)
    return false if classroom.blank?

    classroom.classrooms_grades.any? do |classroom_grade|
      infantil_grade?(classroom_grade.grade)
    end
  end

  def teacher_discipline_ids_for_classroom(classroom)
    linked = TeacherClassroomAndDisciplineFetcher.fetch!(
      current_teacher.id,
      current_unity,
      current_school_year,
      classroom
    )

    (linked[:disciplines] || []).select { |discipline| discipline.grouper == false && discipline.descriptor == false }.map(&:id)
  end

  def classroom_has_lessons_on_date?(classroom:, date:)
    weekday = lessons_board_weekday_for_date(date)
    LessonsBoardLessonWeekday
      .by_classroom(classroom.id)
      .by_weekday(weekday)
      .exists?
  end

  def schedule_unavailable_message_for_knowledge_areas(classroom:, date:, schedule_ids:)
    weekday = lessons_board_weekday_for_date(date)
    classroom_has_lessons = LessonsBoardLessonWeekday
                            .by_classroom(classroom.id)
                            .by_weekday(weekday)
                            .exists?

    message_key = if schedule_ids.blank?
                    classroom_has_lessons ? :no_knowledge_areas_on_lessons_board_for_date : :no_lessons_on_lessons_board_for_date
                  else
                    :no_knowledge_areas_on_lessons_board_for_date
                  end

    lessons_board_date_message(message_key, date)
  end

  def knowledge_areas_matching_schedule(knowledge_areas, classroom:, date:)
    board_discipline_ids = schedule_discipline_ids_for_classroom_weekday(
      classroom_id: classroom.id,
      date: date
    )

    return [] if board_discipline_ids.blank?

    filtered = knowledge_areas.select do |knowledge_area|
      knowledge_area.disciplines.any? { |discipline| board_discipline_ids.include?(discipline.id) }
    end

    filtered.presence || knowledge_areas
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

  def discipline_ids_on_classroom_lessons_board(classroom_id)
    @discipline_ids_on_classroom_lessons_board ||= {}
    @discipline_ids_on_classroom_lessons_board[classroom_id] ||= LessonsBoardLessonWeekday
      .by_classroom(classroom_id)
      .joins(:teacher_discipline_classroom)
      .pluck('teacher_discipline_classrooms.discipline_id')
      .uniq
  end

  def disciplines_without_lessons_board_allocation(disciplines, classroom)
    board_discipline_ids = discipline_ids_on_classroom_lessons_board(classroom.id)
    disciplines.select { |discipline| !board_discipline_ids.include?(discipline.id) }
  end

  def teacher_has_discipline_without_lessons_board_allocation?(classroom, discipline_ids)
    board_discipline_ids = discipline_ids_on_classroom_lessons_board(classroom.id)
    (discipline_ids - board_discipline_ids).present?
  end

  def teacher_make_up_absences_on_date(classroom:, date:)
    TeacherAbsence
      .by_teacher(current_teacher.id)
      .with_make_up
      .where(make_up_date: date)
      .for_classroom_or_unity(classroom.id, classroom.unity_id)
  end

  def teacher_has_make_up_on_date?(classroom:, date:)
    teacher_make_up_absences_on_date(classroom: classroom, date: date).exists? ||
      optional_holiday_make_up_on_date?(classroom: classroom, date: date)
  end

  def optional_holiday_make_up_on_date?(classroom:, date:, period: nil)
    OptionalHoliday.make_up_on_date?(
      classroom: classroom,
      date: date,
      period: period,
      unity_id: classroom.unity_id
    )
  end

  def optional_holiday_blocks_frequency?(classroom:, date:, period: nil)
    OptionalHoliday.blocks_frequency?(
      classroom: classroom,
      date: date,
      period: period,
      unity_id: classroom.try(:unity_id)
    )
  end

  def disciplines_for_make_up_date(disciplines, classroom, date)
    absences = teacher_make_up_absences_on_date(classroom: classroom, date: date).to_a
    if absences.present?
      specific_discipline_ids = absences.map(&:discipline_id).compact.uniq
      if specific_discipline_ids.present?
        return disciplines.select { |discipline| specific_discipline_ids.include?(discipline.id) }
      end

      return disciplines
    end

    return disciplines if optional_holiday_make_up_on_date?(classroom: classroom, date: date)

    []
  end

  def knowledge_areas_for_make_up_date(knowledge_areas, classroom, date)
    absences = teacher_make_up_absences_on_date(classroom: classroom, date: date).to_a
    if absences.present?
      specific_discipline_ids = absences.map(&:discipline_id).compact.uniq
      if specific_discipline_ids.present?
        return knowledge_areas.select do |knowledge_area|
          knowledge_area.disciplines.any? { |discipline| specific_discipline_ids.include?(discipline.id) }
        end
      end

      return knowledge_areas
    end

    return knowledge_areas if optional_holiday_make_up_on_date?(classroom: classroom, date: date)

    []
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

    disciplines_without_board = disciplines_without_lessons_board_allocation(all_disciplines, classroom)
    if disciplines_without_board.present?
      return { disciplines: disciplines_without_board, message: nil }
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
    return { knowledge_areas: knowledge_areas, message: nil } if infantil_classroom?(classroom)
    return { knowledge_areas: knowledge_areas, message: nil } if saturday_school_day_without_equivalent_weekday?(
      classroom: classroom,
      date: record_date
    )

    matched_knowledge_areas = knowledge_areas_matching_schedule(
      knowledge_areas,
      classroom: classroom,
      date: record_date
    )
    if matched_knowledge_areas.present?
      return { knowledge_areas: matched_knowledge_areas, message: nil }
    end

    make_up_knowledge_areas = knowledge_areas_for_make_up_date(knowledge_areas, classroom, record_date)
    if make_up_knowledge_areas.present?
      return { knowledge_areas: make_up_knowledge_areas, message: nil }
    end

    teacher_discipline_ids = teacher_discipline_ids_for_classroom(classroom)
    scheduled_teacher_discipline_ids = linked_discipline_ids_on_schedule(
      classroom_id: classroom.id,
      date: record_date,
      discipline_ids: teacher_discipline_ids
    )

    {
      knowledge_areas: [],
      message: schedule_unavailable_message_for_knowledge_areas(
        classroom: classroom,
        date: record_date,
        schedule_ids: scheduled_teacher_discipline_ids
      )
    }
  end

  # Professores da turma no mesmo turno, inclusive vínculos inativos/desativados
  # (substituição). Sem período específico, fica só o professor logado.
  def teacher_ids_for_classroom_period(classroom_id:, period: nil)
    current_id = current_teacher&.id
    return Array(current_id) if classroom_id.blank?

    period = period.presence || teacher_period_for_classroom(classroom_id)
    period_value = period.to_i

    unless period_value.positive? && period_value != Periods::FULL.to_i
      return Array(current_id)
    end

    scope = TeacherDisciplineClassroom.unscoped.where(classroom_id: classroom_id)
    year = Classroom.unscoped.where(id: classroom_id).limit(1).pluck(:year).first
    scope = scope.where(year: year) if year.present?

    ids = scope.where(period: [period_value, period_value.to_s])
               .distinct
               .pluck(:teacher_id)
               .compact

    ids | Array(current_id)
  end

  def teacher_period_for_classroom(classroom_id)
    return if current_teacher.blank? || classroom_id.blank?

    TeacherPeriodFetcher.new(
      current_teacher.id,
      classroom_id,
      try(:current_user).try(:current_discipline_id)
    ).teacher_period
  end

  def prefer_current_teacher_records(records)
    return records if current_teacher.blank?

    own = records.select { |record| record.content_record&.teacher_id == current_teacher.id }
    own.presence || records
  end
end
