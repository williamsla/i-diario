class AvaliationsController < ApplicationController
  has_scope :page, default: 1, only: [:index]
  has_scope :per, default: 10, only: [:index]

  respond_to :html, :js, :json

  before_action :require_current_classroom
  before_action :require_current_discipline
  before_action :require_current_teacher, except: [:search]
  before_action :set_number_of_classes, only: [
    :new, :create, :edit, :update, :multiple_classrooms, :create_multiple_classrooms
  ]
  before_action :require_allow_to_modify_prev_years, only: [
    :create, :update, :destroy, :create_multiple_classrooms, :create_batch
  ]

  def index
    @classrooms = [current_user_classroom]
    @disciplines = [current_user_discipline]

    @classroom = current_user_classroom
    @steps_for_picker = StepsFetcher.new(@classroom).steps.to_a
    @exam_report_use_classroom_step_field = SchoolCalendarClassroomStep.by_classroom(@classroom.id).ordered.any?

    authorize Avaliation.new(classroom: @classroom, discipline: current_user_discipline), :index?
    respond_to do |format|
      format.html
      format.js { head :no_content }
    end
  end

  def new
    return if test_settings_redirect
    return if score_types_redirect
    return if not_allow_numerical_exam

    fetch_linked_by_teacher unless current_user.current_role_is_admin_or_employee?

    @numeric_grades = current_user_classroom.classrooms_grades.by_score_type(ScoreTypes::NUMERIC)
    @numeric_and_concept_grades = current_user_classroom.classrooms_grades.by_score_type(ScoreTypes::NUMERIC_AND_CONCEPT)

    @grades ||= (@numeric_grades + @numeric_and_concept_grades).map(&:grade)

    @avaliation = resource
    @avaliation.school_calendar = current_school_calendar
    @avaliation.classroom = current_user_classroom
    @avaliation.discipline = current_user_discipline
    @avaliation.test_date = Time.zone.today

    if params[:step_id].present?
      step = StepsFetcher.new(current_user_classroom).step_by_id(params[:step_id])
      if step
        today = Time.zone.today
        start_d = step.start_at.to_date
        end_d = step.end_at.to_date
        @avaliation.test_date = [[today, end_d].min, start_d].max
      else
        flash[:alert] = t('avaliations.by_step.invalid_step')
        redirect_to avaliations_path and return
      end
    end

    fetch_disciplines_by_classroom

    authorize resource
  end

  def new_batch
    return if test_settings_redirect
    return if score_types_redirect
    return if not_allow_numerical_exam

    @step = StepsFetcher.new(current_user_classroom).step_by_id(params[:step_id])
    unless @step
      flash[:alert] = t('avaliations.by_step.invalid_step')
      redirect_to avaliations_path and return
    end

    @test_setting = TestSettingFetcher.current(
      current_user_classroom,
      @step,
      discipline: current_user_discipline
    )
    unless @test_setting
      flash[:error] = t('errors.avaliations.require_setting')
      redirect_to avaliations_path and return
    end

    @recorded_at = batch_step_end_date(@step)
    @assessments_count = params[:assessments_count].presence
    @batch_calculation = params[:batch_calculation].presence || 'arithmetic'

    ctx = AvaliationBatchGrades::BuildContext.new(
      classroom: current_user_classroom,
      discipline: current_user_discipline,
      step: @step,
      test_setting: @test_setting,
      recorded_at: @recorded_at,
      assessments_count: @assessments_count,
      teacher_calculation: @batch_calculation,
      column_labels: batch_column_labels_param
    )

    unless ctx.supported?
      flash[:alert] = ctx.errors.join('; ')
      redirect_to avaliations_path and return
    end

    @batch = ctx.to_h
    requested_count = @assessments_count.to_i
    min_allowed = @batch[:minimum_assessments_count].to_i
    if @assessments_count.present? && requested_count < min_allowed
      flash.now[:alert] = t('avaliations.batch.assessments_count_reduction_blocked', min: min_allowed)
    end

    authorize Avaliation.new(classroom: current_user_classroom, discipline: current_user_discipline), :new?
  end

  def create_batch
    return if test_settings_redirect
    return if score_types_redirect
    return if not_allow_numerical_exam

    unless params[:avaliation_batch].present?
      flash[:alert] = t('avaliations.batch.invalid_form')
      redirect_to avaliations_path and return
    end

    authorize Avaliation.new(classroom: current_user_classroom, discipline: current_user_discipline), :create?

    @step = StepsFetcher.new(current_user_classroom).step_by_id(batch_step_id)
    unless @step
      flash[:alert] = t('avaliations.by_step.invalid_step')
      redirect_to avaliations_path and return
    end

    test_setting = TestSettingFetcher.current(
      current_user_classroom,
      @step,
      discipline: current_user_discipline
    )
    unless test_setting
      flash[:error] = t('errors.avaliations.require_setting')
      redirect_to avaliations_path and return
    end

    recorded_at = batch_step_end_date(@step)

    service = AvaliationBatchGrades::SaveService.new(
      classroom: current_user_classroom,
      discipline: current_user_discipline,
      step: @step,
      teacher: current_teacher,
      current_user: current_user,
      school_calendar: current_school_calendar,
      test_setting: test_setting,
      recorded_at: recorded_at,
      assessments_count: batch_params[:assessments_count],
      notes_params: batch_notes_params,
      teacher_calculation: batch_params[:batch_calculation],
      column_weights: batch_column_weights_param,
      column_labels: batch_column_labels_param,
      unlocked_student_ids: batch_unlocked_student_ids_param
    )

    if service.call
      redirect_to avaliations_path, notice: t('avaliations.batch.saved')
    else
      flash.now[:alert] = service.errors.join('; ')
      @test_setting = test_setting
      @recorded_at = recorded_at
      @assessments_count = batch_params[:assessments_count]
      ctx = AvaliationBatchGrades::BuildContext.new(
        classroom: current_user_classroom,
        discipline: current_user_discipline,
        step: @step,
        test_setting: test_setting,
        recorded_at: @recorded_at,
        assessments_count: @assessments_count,
        teacher_calculation: batch_params[:batch_calculation],
        column_labels: batch_column_labels_param
      )
      @batch = ctx.supported? ? ctx.to_h : {}
      render :new_batch
    end
  end

  def multiple_classrooms
    return if test_settings_redirect
    return if score_types_redirect
    return if not_allow_numerical_exam

    fetch_linked_by_teacher unless current_user.current_role_is_admin_or_employee?

    set_avaliation_multiple_creator_by_user

    authorize Avaliation.new

    test_settings
  end

  def set_avaliation_multiple_creator_by_user
    @avaliation_multiple_creator_form = AvaliationMultipleCreatorForm.new.localized
    @avaliation_multiple_creator_form.school_calendar_id = current_school_calendar.id
    @avaliation_multiple_creator_form.discipline_id = current_user_discipline.id
    @avaliation_multiple_creator_form.unity_id = current_unity.id
    @avaliation_multiple_creator_form.load_avaliations!(current_teacher.id, current_school_calendar.year)
  end

  def create_multiple_classrooms
    authorize Avaliation.new
    params_avaliation_multiple = params[:avaliation_multiple_creator_form].to_unsafe_h

    @avaliation_multiple_creator_form = AvaliationMultipleCreatorForm.new(
      params_avaliation_multiple.merge(teacher_id: current_teacher_id)
    )

    if @avaliation_multiple_creator_form.save
      respond_with @avaliation_multiple_creator_form, location: avaliations_path
    else
      test_settings
      fetch_linked_by_teacher unless current_user.current_role_is_admin_or_employee?
      fetch_disciplines_by_classroom

      render :multiple_classrooms
    end
  end

  def create
    resource.localized.assign_attributes(resource_params)
    resource.school_calendar = current_school_calendar
    resource.teacher_id = current_teacher_id

    authorize resource
    if resource.save
      respond_to_save
    else
      @avaliation = resource
      fetch_linked_by_teacher unless current_user.current_role_is_admin_or_employee?
      fetch_disciplines_by_classroom

      test_settings

      render :new
    end
  end

  def edit
    fetch_linked_by_teacher unless current_user.current_role_is_admin_or_employee?

    @avaliation = resource
    @grades = @avaliation.grades

    test_settings
    fetch_disciplines_by_classroom

    authorize @avaliation
  end

  def update
    @avaliation = resource
    @avaliation.localized.assign_attributes(resource_params)
    @avaliation.teacher_id = current_teacher_id
    @avaliation.current_user = current_user

    authorize @avaliation

    if resource.grade_ids.empty?
      flash[:error] = 'Série não pode ficar em branco'
      test_settings

      return render :edit
    else
      flash.clear
    end

    if resource.save
      respond_to_save
    else
      fetch_linked_by_teacher unless current_user.current_role_is_admin_or_employee?
      fetch_disciplines_by_classroom
      test_settings

      render :edit
    end
  end

  def destroy
    authorize resource

    if params[:step_id].present?
      step = StepsFetcher.new(current_user_classroom).step_by_id(params[:step_id])
      unless step && batch_destroy_allowed_for_step?(resource, step)
        flash[:alert] = t('avaliations.batch.destroy_forbidden')
        redirect_to avaliations_path
        return
      end

      svc = AvaliationBatchGrades::DestroyColumnService.new(avaliation: resource)
      if svc.call
        flash[:notice] = t('avaliations.batch.column_destroyed')
      else
        flash[:alert] = svc.error.presence || t('avaliations.batch.destroy_failed')
      end
      redirect_to new_batch_avaliations_path(step_id: step.id)
      return
    end

    resource.destroy

    respond_with resource, location: avaliations_path
  end

  def history
    @avaliation = Avaliation.find(params[:id])

    authorize @avaliation

    respond_with @avaliation
  end

  def search
    @avaliations = apply_scopes(Avaliation).ordered

    render json: @avaliations
  end

  def show
    render json: resource
  end

  def set_type_score_for_discipline
    return if params[:classroom_id].blank? && params[:discipline_id].blank?

    classroom = Classroom.find(params[:classroom_id])
    discipline = Discipline.find(params[:discipline_id])

    score_types = []

    classroom.classrooms_grades.each do |classroom_grade|
      exam_rule = classroom_grade.exam_rule

      next if exam_rule.blank?

      differentiated_exam_rule = exam_rule.differentiated_exam_rule

      if differentiated_exam_rule.blank? || !classroom_grade.classroom.has_differentiated_students?
        score_types << discipline_score_type_by_exam_rule(exam_rule, classroom_grade.classroom, discipline)
      end

      score_types << discipline_score_type_by_exam_rule(differentiated_exam_rule, classroom_grade.classroom, discipline)
    end

    available_score_types = score_types.uniq

    render json: true if available_score_types.any? { |discipline_score_type| discipline_score_type == ScoreTypes::NUMERIC }
  end

  def discipline_score_type_by_exam_rule(exam_rule, classroom, discipline)
    return if exam_rule.blank?
    return unless (score_type = exam_rule.score_type)
    return if score_type == ScoreTypes::DONT_USE
    return score_type if [ScoreTypes::NUMERIC, ScoreTypes::CONCEPT].include?(score_type)

    TeacherDisciplineClassroom.find_by(
      classroom: classroom,
      teacher: current_teacher,
      discipline: discipline
    ).score_type
  end

  def set_avaliation_setting
    return if params[:classroom_id].blank?

    classroom = Classroom.find(params[:classroom_id])

    year_test_setting = TestSetting.where(year: classroom.year)

    test_settings ||= general_by_school_test_setting(year_test_setting) ||
                      general_test_setting(year_test_setting) ||
                      by_school_term_test_setting(year_test_setting)

    test_setting_tests = TestSettingTest.where(test_setting: test_settings)

    render json: test_setting_tests
  end

  def set_grades_by_classrooms
    return if params[:classroom_id].blank?

    classroom = Classroom.find(params[:classroom_id])

    grades = classroom.grades.ordered

    render json: grades
  end

  def check_if_allow_numeric_exam
    return if params[:classroom_id].blank?

    classroom = Classroom.find(params[:classroom_id])

    grades_by_numerical_exam = classroom.classrooms_grades
                                        .by_score_type(ScoreTypes::NUMERIC)
                                        .map(&:grade)

    render json: true if grades_by_numerical_exam.present?
  end

  private

  def batch_step_id
    params.dig(:avaliation_batch, :step_id).presence || params[:step_id]
  end

  def batch_params
    params.fetch(:avaliation_batch, ActionController::Parameters.new).permit(
      :step_id, :assessments_count, :batch_calculation, column_weights: [], column_labels: []
    )
  end

  def batch_column_weights_param
    raw = params.to_unsafe_h.dig(:avaliation_batch, :column_weights) ||
          params.to_unsafe_h.dig('avaliation_batch', 'column_weights')
    return [] if raw.blank?

    Array(raw).map(&:presence)
  end

  def batch_column_labels_param
    raw = params.to_unsafe_h.dig(:avaliation_batch, :column_labels) ||
          params.to_unsafe_h.dig('avaliation_batch', 'column_labels')
    return [] if raw.blank?

    Array(raw).map { |v| v.to_s.strip.presence }
  end

  def batch_notes_params
    raw = params.dig(:avaliation_batch, :notes)
    return {} if raw.blank?

    raw.respond_to?(:permit!) ? raw.permit!.to_h : raw.to_h
  end

  def batch_unlocked_student_ids_param
    raw = params.to_unsafe_h.dig(:avaliation_batch, :unlocked_student_ids) ||
          params.to_unsafe_h.dig('avaliation_batch', 'unlocked_student_ids')
    Array(raw)
  end

  def batch_step_end_date(step)
    (step.end_at.presence || step.start_at).to_date
  end

  def batch_destroy_allowed_for_step?(avaliation, step)
    return false unless avaliation.classroom_id == current_user_classroom.id
    return false unless avaliation.discipline_id == current_user_discipline.id

    td = avaliation.test_date.to_date
    return false unless td >= step.start_at.to_date && td <= step.end_at.to_date

    return true if current_user.current_role_is_admin_or_employee?

    Avaliation.teacher_avaliations(
      current_teacher.id,
      current_user_classroom.id,
      current_user_discipline.id
    ).where(id: avaliation.id).exists?
  end

  def fetch_linked_by_teacher
    @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(current_teacher.id, current_unity, current_school_year)
    @classrooms = @fetch_linked_by_teacher[:classrooms].by_score_type(ScoreTypes::NUMERIC)
    @disciplines = @fetch_linked_by_teacher[:disciplines].by_score_type(ScoreTypes::NUMERIC).not_descriptor
    @classroom_grades = @fetch_linked_by_teacher[:classroom_grades]
    @grades = @classroom_grades.map(&:grade).uniq
  end

  def respond_to_save
    if params[:commit] == I18n.t('avaliations.form.save_and_edit_daily_notes')
      creator = DailyNoteCreator.new(avaliation_id: resource.id)
      creator.find_or_create

      @daily_note = creator.daily_note

      if @daily_note.persisted?
        redirect_to edit_daily_note_path(@daily_note)
      else
        render 'daily_notes/new'
      end
    else
      redirect_to avaliations_path
    end
  end

  def disciplines_for_multiple_classrooms
    if current_user.current_role_is_admin_or_employee?
      return @disciplines ||= Discipline.by_unity_id(current_unity.id).by_teacher_id(current_teacher.id).ordered
    end

    fetch_linked_by_teacher
    @disciplines
  end
  helper_method :disciplines_for_multiple_classrooms

  def classrooms_for_multiple_classrooms
    return [] if @avaliation_multiple_creator_form.discipline_id.blank?

    @classrooms_for_multiple_classrooms ||= Classroom.by_unity(current_unity.id)
                                                     .by_teacher_id(current_teacher.id)
                                                     .by_teacher_discipline(
                                                       @avaliation_multiple_creator_form.discipline_id
                                                     ).ordered
  end
  helper_method :classrooms_for_multiple_classrooms

  def set_number_of_classes
    @number_of_classes = current_school_calendar.number_of_classes
  end

  def resource
    @resource ||= case params[:action]
                  when 'new', 'create'
                    Avaliation.new
                  when 'edit', 'update', 'destroy', 'show'
                    Avaliation.find(params[:id])
                  end
  end

  def resource_params
    parameters = params.require(:avaliation).permit(
      :test_setting_id,
      :classroom_id,
      :discipline_id,
      :test_date,
      :classes,
      :description,
      :test_setting_test_id,
      :weight,
      :observations,
      :grade_ids
    )

    parameters[:grade_ids] = parameters[:grade_ids].split(',')

    parameters
  end

  def interpolation_options
    if action_name == 'destroy'
      reasons = []

      if resource.errors[:test_date].include?(t('errors.messages.not_allowed_to_post_in_date'))
        reasons << t('errors.messages.not_allowed_to_post_in_date')
      end

      reasons << t('avaliation.grades_avoid_destroy') unless resource.grades_allow_destroy
      reasons << t('avaliation.recovery_avoid_destroy') unless resource.recovery_allow_destroy

      { reason: reasons.join(' e ') }
    elsif ['create', 'create_multiple_classrooms'].include?(action_name)
      classrooms = if resource
                     [resource.classroom.description]
                   else
                     classroom_records = params[:avaliation_multiple_creator_form][:avaliations_attributes].values
                     included = classroom_records.select { |classroom_record| classroom_record['include'] == '1' }
                     included.map { |included_record| Classroom.find(included_record['classroom_id']).description }
                   end

      { resource_name: I18n.t('activerecord.models.avaliation.one'), classrooms: classrooms.join(', ') }
    end
  end

  def test_settings_redirect
    !test_setting? && redirect_to(avaliations_path)
  end

  def test_setting?
    return true if test_settings

    flash[:error] = t('errors.avaliations.require_setting')

    false if current_user.current_role_is_admin_or_employee?
  end

  def test_settings
    return unless (year_test_setting = TestSetting.where(year: current_user_classroom.year))

    @test_settings ||= general_by_school_test_setting(year_test_setting) ||
                       general_test_setting(year_test_setting) ||
                       by_school_term_test_setting(year_test_setting)
  end

  def general_by_school_test_setting(year_test_setting, classroom = nil)
    classroom ||= classroom || current_user_classroom
    grade_ids = classroom.grade_ids
    grade_ids = classroom.classrooms_grades.pluck(:grade_id) if grade_ids.blank?

    year_test_setting.where(exam_setting_type: ExamSettingTypes::GENERAL_BY_SCHOOL)
                     .by_unities(classroom.unity)
                     .where(
                       "grades && ARRAY[?]::integer[] OR grades = '{}'",
                       grade_ids.compact.uniq
                     )
                     .presence
  end

  def general_test_setting(year_test_setting)
    year_test_setting.where(exam_setting_type: ExamSettingTypes::GENERAL).presence
  end

  def by_school_term_test_setting(year_test_setting)
    year_test_setting.where(exam_setting_type: ExamSettingTypes::BY_SCHOOL_TERM)
                     .order(:school_term_type_step_id)
                     .presence
  end

  def score_types_redirect
    available_score_types = (teacher_differentiated_discipline_score_types + teacher_discipline_score_types).uniq

    return if available_score_types.any? { |discipline_score_type| discipline_score_type == ScoreTypes::NUMERIC || discipline_score_type == ScoreTypes::NUMERIC_AND_CONCEPT }

    if current_user.current_role_is_admin_or_employee?
      redirect_to avaliations_path, alert: t('avaliation.numeric_exam_absence')
    else
      flash.now[:alert] = t('avaliation.numeric_exam_absence')
      return false
    end
  end

  def not_allow_numerical_exam
    grades_by_numerical_exam = current_user.classroom.classrooms_grades.by_score_type(ScoreTypes::NUMERIC).map(&:grade)
    grades_by_numerical_and_concept_exam = current_user.classroom.classrooms_grades.by_score_type(ScoreTypes::NUMERIC_AND_CONCEPT).map(&:grade)

    return if grades_by_numerical_exam.present? || grades_by_numerical_and_concept_exam.present?

    if current_user.current_role_is_admin_or_employee?
      redirect_to avaliations_path, alert: t('avaliation.grades_not_allow_numeric_exam')
    else
      flash.now[:alert] = t('avaliation.grades_not_allow_numeric_exam')
      return false
    end
  end

  def fetch_disciplines_by_classroom
    return if current_user.current_role_is_admin_or_employee?

    classrooms = [@avaliation.classroom] if @avaliation&.classroom

    classrooms ||= @avaliation_multiple_creator_form.avaliations.map(&:classroom)

    @disciplines = @disciplines.by_classroom_id(classrooms.map(&:id)).not_descriptor
    @grades = @classroom_grades.by_classroom_id(classrooms.map(&:id)).map(&:grade).uniq
  end
end
