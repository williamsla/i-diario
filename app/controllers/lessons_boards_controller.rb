class LessonsBoardsController < ApplicationController
  has_scope :page, default: 1
  has_scope :per, default: 10

  def index
    @lessons_boards = LessonBoardsFetcher.new(current_user).lesson_boards(archived: show_archived?)
    @lessons_boards = apply_scopes(@lessons_boards).filter(filtering_params(params[:search]))
    authorize @lessons_boards
  end

  def show
    @lessons_board = resource

    @classrooms = classrooms_to_select2(resource.classrooms_grade.grade_id, resource.classrooms_grade.classroom.unity&.id)
    @teachers = teachers_to_select2(resource.classrooms_grade.classroom.id, resource.period, resource.grade_id)

    ActiveRecord::Associations::Preloader.new.preload(
      @lessons_board,
      lessons_board_lessons: :lessons_board_lesson_weekdays
    )

    validate_lessons_number

    authorize @lessons_board
  end

  def new
    unities

    authorize resource
  end

  def create
    authorize resource

    selected_grade_ids = selected_grade_ids_param
    return create_single_lessons_board if selected_grade_ids.blank?

    if create_multiple_lessons_boards(selected_grade_ids)
      respond_with resource, location: lessons_boards_path
    else
      render :new
    end
  end

  def edit
    @lessons_board = resource

    @classrooms = Classroom.where(unity_id: resource.classrooms_grade.classroom&.unity&.id)
    @teachers = teachers_to_select2(resource.classrooms_grade.classroom.id, resource.period, resource.grade_id)
    
    validate_lessons_number

    authorize @lessons_board
  end

  def update
    resource.assign_attributes(resource_params.to_h)

    authorize resource

    if resource.save
      respond_with resource, location: lessons_boards_path(show_archived: resource.discarded? ? 1 : nil)
    else
      render :edit
    end
  end

  def destroy
    authorize resource

    archived_until = parse_archived_until(params[:archived_until])
    if archived_until.blank?
      flash[:alert] = 'Informe até que dia esse quadro de aulas funcionou.'
      return redirect_to lessons_boards_path
    end

    discard_time = archived_until.end_of_day
    resource.discard
    resource.update_column(:discarded_at, discard_time)

    respond_with resource, location: lessons_boards_path
  end

  def undiscard
    authorize resource

    if active_board_conflict?(resource)
      flash[:alert] = I18n.t('lessons_boards.undiscard.conflict')
      return redirect_to lessons_boards_path(show_archived: 1)
    end

    resource.undiscard
    flash[:notice] = I18n.t('lessons_boards.undiscard.notice')
    redirect_to lessons_boards_path
  end

  def update_archived_until
    authorize resource

    unless resource.discarded?
      flash[:alert] = I18n.t('lessons_boards.update_archived_until.only_archived')
      return redirect_to lessons_boards_path
    end

    archived_until = parse_archived_until(params[:archived_until])
    if archived_until.blank?
      flash[:alert] = I18n.t('lessons_boards.update_archived_until.date_required')
      return redirect_to lessons_boards_path(show_archived: 1)
    end

    first_day = calendar_first_day_for(resource)
    if first_day.present? && archived_until < first_day
      flash[:alert] = I18n.t('lessons_boards.update_archived_until.before_calendar')
      return redirect_to lessons_boards_path(show_archived: 1)
    end

    resource.update_column(:discarded_at, archived_until.end_of_day)
    flash[:notice] = I18n.t('lessons_boards.update_archived_until.notice')
    redirect_to lessons_boards_path(show_archived: 1)
  end

  def purge
    authorize resource

    unless params[:confirm_permanent_delete].to_s == '1'
      flash[:alert] = I18n.t('lessons_boards.purge.confirmation_required')
      return redirect_to lessons_boards_path(show_archived: resource.discarded? ? 1 : nil)
    end

    resource.discard if resource.kept?

    unless purge_lessons_board!(resource)
      flash[:alert] = I18n.t('lessons_boards.purge.calendar_required')
      return redirect_to lessons_boards_path(show_archived: resource.discarded? ? 1 : nil)
    end

    flash[:notice] = I18n.t('lessons_boards.purge.notice')
    redirect_to lessons_boards_path
  end

  def filtering_params(params)
    params = {} unless params

    params.slice(
      :by_year,
      :by_unity,
      :by_grade,
      :by_classroom
    )
  end

  def lesson_unities
    boards_scope = lessons_boards_for_filters

    lessons_unities = if user_role_administrator?
                        boards_scope.by_unity(unities_id)
                                    .map(&:unity_id)
                                    .uniq
                      elsif current_user.employee?
                        roles_ids = Role.where(access_level: AccessLevel::EMPLOYEE).pluck(:id)
                        unities_user = UserRole.where(user_id: current_user.id, role_id: roles_ids).pluck(:unity_id)

                        boards_scope.by_unity(unities_user)
                                    .map(&:unity_id)
                                    .uniq
                      else
                        unities
                      end

    Unity.where(id: lessons_unities).ordered
  end
  helper_method :lesson_unities

  def user_role_administrator?
    @role_administrator ||= current_user.reload_current_user_role&.role&.administrator?
  end

  def unities
    @unities ||= fetch_unities
  end

  def fetch_unities
    return [current_user_unity] unless user_role_administrator?

    Unity.joins(:school_calendars)
         .where(school_calendars: { year: current_user_school_year })
         .ordered
  end

  def unities_id
    unities.map(&:id)
  end

  def lesson_grades
    lessons_grades = lessons_boards_for_filters.by_unity(unities_id)
                                 .map(&:grade_id)
                                 .uniq

    Grade.find(lessons_grades)
  end

  helper_method :lesson_grades

  def lesson_classrooms
    lessons_classrooms = lessons_boards_for_filters.by_unity(unities_id)
                                     .map(&:classroom_id)
                                     .uniq

    Classroom.find(lessons_classrooms)
  end

  helper_method :lesson_classrooms

  def resource
    @lessons_board ||= case params[:action]
                       when 'edit', 'update', 'show', 'destroy', 'undiscard', 'purge', 'update_archived_until'
                         LessonsBoard.with_discarded.find(params[:id])
                       else
                         LessonsBoard.new
                       end.localized
  end

  def show_archived?
    params[:show_archived].to_s == '1'
  end
  helper_method :show_archived?

  def lessons_boards_for_filters
    return LessonsBoard unless show_archived?

    LessonsBoard.with_discarded.discarded
                .joins(classrooms_grade: :classroom)
                .joins(<<-SQL.squish)
                  INNER JOIN school_calendars sc
                    ON sc.unity_id = classrooms.unity_id
                   AND sc.year = classrooms.year
                  INNER JOIN (
                    SELECT school_calendar_id, MIN(start_at) AS first_day
                    FROM school_calendar_steps
                    GROUP BY school_calendar_id
                  ) sc_start ON sc_start.school_calendar_id = sc.id
                SQL
                .where('lessons_boards.discarded_at >= sc_start.first_day')
  end

  def resource_params
    params.require(:lessons_board).permit(:classrooms_grade_id, :period,
                                          lessons_board_lessons_attributes: [
                                            :id, :lesson_number, :_destroy,
                                            lessons_board_lesson_weekdays_attributes: [
                                              :id, :weekday, :teacher_discipline_classroom_id, :_destroy
                                            ]
                                          ])
  end

  def classroom_grade
    return if params[:grade_id].blank? && params[:classroom_id].blank?

    render json: ClassroomsGrade.find_by(
      grade_id: params[:grade_id],
      classroom_id: params[:classroom_id]
    )&.id
  end

  def period
    return if params[:classroom_id].blank?

    render json: Classroom.find(params[:classroom_id])
                          .period
  end

  def number_of_lessons
    return if params[:classroom_id].blank?

    render json: Classroom.find(params[:classroom_id])
                          .number_of_classes
  end

  def teachers_classroom
    return if params[:classroom_id].blank? || params[:grade_id].blank?

    render json: teachers_to_select2(params[:classroom_id], nil, params[:grade_id])
  end

  def teachers_classroom_period
    return if params[:classroom_id].blank? || params[:period].blank? || params[:grade_id].blank?

    render json: teachers_to_select2(params[:classroom_id], params[:period], params[:grade_id])
  end

  def classrooms_filter
    return if params[:grade_id].blank? && params[:unity_id].blank?

    render json: classrooms_to_select2(params[:grade_id], params[:unity_id])
  end

  def grades_by_unity
    return if params[:unity_id].blank?

    render json: grades_by_unity_to_select2(params[:unity_id])
  end

  def grades_by_classroom
    return if params[:classroom_id].blank?

    classroom = Classroom.find(params[:classroom_id])
    grades = Grade.includes(:course)
                 .joins(:classrooms_grades)
                 .where(classrooms_grades: { classroom_id: params[:classroom_id] })
                 .ordered

    render json: grades.map do |grade|
      OpenStruct.new(
        id: grade.id,
        name: grade.description.to_s,
        text: grade.description.to_s,
        selected: grade.id == params[:grade_id].to_i || (classroom.multi_grade? && grades.one?)
      )
    end
  end

  def not_exists_by_classroom
    return if params[:classroom_id].blank?

    board = LessonsBoard.by_classroom(params[:classroom_id]).first
    render json: { id: board&.id }
  end

  def not_exists_by_classroom_and_grade
    return if params[:classroom_id].blank? || params[:grade_id].blank?

    board = LessonsBoard.by_classroom(params[:classroom_id])
                        .by_grade(params[:grade_id])
                        .first
    render json: { id: board&.id }
  end

  def not_exists_by_classroom_and_period
    return if params[:classroom_id].blank?

    lessons_boards = LessonsBoard.by_classroom(params[:classroom_id])
                                 .by_period(params[:period])
    lessons_boards = lessons_boards.by_grade(params[:grade_id]) if params[:grade_id].present?

    render json: { id: lessons_boards.first&.id }
  end

  def classroom_multi_grade
    return if params[:classroom_id].blank?

    classroom = Classroom.find(params[:classroom_id])
    render json: classroom.multi_grade?
  end

  def teacher_in_other_classroom
    any_blank_param = (
      params[:teacher_discipline_classroom_id].blank? ||
      params[:lesson_number].blank? ||
      params[:weekday].blank? ||
      params[:classroom_id].blank? ||
      params[:period].blank?
    )

    return if any_blank_param

    render json: linked_teacher(params[:teacher_discipline_classroom_id], params[:lesson_number], params[:weekday],
                                params[:classroom_id], params[:period])
  end

  def count_lessons
    classroom_id = params[:classroom_id]
    discipline_id = params[:discipline_id]
    date = Date.strptime(params[:date], "%d/%m/%Y")

    total_aulas = LessonBoardsFetcher.new(current_user).count_lessons_including_make_up(
      classroom_id,
      discipline_id,
      date
    )

    render json: total_aulas
  end

  private

  def create_single_lessons_board
    resource.assign_attributes(resource_params.to_h)

    if resource.save
      respond_with resource, location: lessons_boards_path
    else
      render :new
    end
  end

  def create_multiple_lessons_boards(grade_ids)
    classroom_id = params.dig(:lessons_board, :classroom_id)
    period = params.dig(:lessons_board, :period)
    payload = resource_params.to_h.except('classrooms_grade_id')

    ActiveRecord::Base.transaction do
      grade_ids.each do |grade_id|
        classrooms_grade_id = ClassroomsGrade.find_by(classroom_id: classroom_id, grade_id: grade_id)&.id
        raise ActiveRecord::Rollback if classrooms_grade_id.blank?

        lessons_board = LessonsBoard.new(payload.merge(
          classrooms_grade_id: classrooms_grade_id,
          period: period
        ))

        unless lessons_board.save
          copy_errors_to_resource(lessons_board)
          raise ActiveRecord::Rollback
        end
      end
    end

    resource.errors.blank?
  end

  def copy_errors_to_resource(lessons_board)
    lessons_board.errors.full_messages.each do |message|
      resource.errors.add(:base, message)
    end
  end

  def selected_grade_ids_param
    return [] if params[:selected_grade_ids].blank?

    params[:selected_grade_ids].select(&:present?).map(&:to_i).uniq
  end

  def validate_lessons_number
    classroom_lessons = resource.classroom.number_of_classes
    board_lessons = resource.lessons_board_lessons.size

    return if classroom_lessons == board_lessons || classroom_lessons < board_lessons

    build_new_lessons(classroom_lessons, board_lessons)
  end

  def build_new_lessons(classroom_lessons, board_lessons)
    while classroom_lessons > board_lessons
      last_lesson = resource.lessons_board_lessons.size

      if resource.lessons_board_lessons.build(lesson_number: last_lesson + 1)
        board_lessons += 1
      end
    end
  end

  def service
    @service ||= LessonBoardsService.new
  end

  def linked_teacher(teacher_discipline_classroom_id, lesson_number, weekday, classroom, period)
    service.linked_teacher(teacher_discipline_classroom_id, lesson_number, weekday, classroom, period)
  end

  def teachers_to_select2(classroom_id, period, grade_id)
    service.teachers(classroom_id, period, grade_id)
  end

  def classrooms_to_select2(grade_id, unity_id)
    classrooms_to_select2 = []

    classrooms = Classroom.by_unity(unity_id)
                          .by_year(current_user_school_year)
                          .ordered

    classrooms = classrooms.by_grade(grade_id) if grade_id.present?

    classrooms.each do |classroom|
      classrooms_to_select2 << OpenStruct.new(
        id: classroom.id,
        name: classroom.description.to_s,
        text: classroom.description.to_s
      )
    end

    classrooms_to_select2
  end

  def grades_by_unity_to_select2(unity_id)
    grades_to_select2 = []
    grades = Grade.includes(:course)
                  .by_unity(unity_id)
                  .ordered

    grades.each do |grade|
      grades_to_select2 << OpenStruct.new(
        id: grade.id,
        name: grade.description.to_s,
        text: grade.description.to_s
      )
    end

    grades_to_select2
  end

  def parse_archived_until(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def active_board_conflict?(lessons_board)
    LessonsBoard.where(
      classrooms_grade_id: lessons_board.classrooms_grade_id,
      period: lessons_board.period
    ).where.not(id: lessons_board.id).exists?
  end

  def purge_lessons_board!(lessons_board)
    first_day = calendar_first_day_for(lessons_board)
    return false if first_day.blank?

    # Data anterior ao início do calendário: o quadro permanece no banco,
    # mas não entra na lógica de dias letivos (date <= discarded_at).
    exclusion_at = (first_day - 1.day).end_of_day
    lessons_board.update_column(:discarded_at, exclusion_at)
    true
  end

  def calendar_first_day_for(lessons_board)
    classroom = lessons_board.classrooms_grade.classroom
    calendar = CurrentSchoolCalendarFetcher.new(classroom.unity, classroom, classroom.year).fetch
    calendar&.first_day&.to_date
  rescue StandardError
    nil
  end

end
