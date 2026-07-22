class ConceptualExamsController < ApplicationController
  has_scope :page, default: 1
  has_scope :per, default: 10

  before_action :require_current_classroom
  before_action :require_current_teacher
  before_action :require_allow_to_modify_prev_years, only: [:create, :update, :destroy]
  before_action :allow_teacher_modify_prev_years, only: [:create, :update, :create_batch]
  before_action :view_data, only: [:edit, :show]
  before_action :require_batch_layout_enabled, only: [:new_batch, :form_batch, :create_batch]

  def index
    step_id = (params[:filter] || []).delete(:by_step)
    status = (params[:filter] || []).delete(:by_status)

    set_options_by_user

    @conceptual_exam_batch_layout = conceptual_exam_batch_layout?

    if @conceptual_exam_batch_layout
      @classroom = current_user_classroom
      @steps = steps_fetcher(@classroom).steps if @classroom.present?
      authorize ConceptualExam.new(classroom_id: @classroom&.id, student_id: nil)
    else
      @conceptual_exams = fetch_conceptual_exams
      @only_one_conceptual_avaliation = GeneralConfiguration.annual_conceptual_evaluation?
      check_status_and_step(step_id, status)
      authorize @conceptual_exams
    end
  end

  def new
    set_options_by_user
    discipline_score_types = (teacher_differentiated_discipline_score_types + teacher_discipline_score_types).uniq

    not_concept_score = discipline_score_types.none? { |discipline_score_type|
      discipline_score_type == ScoreTypes::CONCEPT || discipline_score_type == ScoreTypes::NUMERIC_AND_CONCEPT
    }

    if not_concept_score
      if current_user.current_role_is_admin_or_employee?
        redirect_to(
          conceptual_exams_path,
          alert: t('conceptual_exams.new.current_discipline_does_not_have_conceptual_exam')
        ) && return
      end

      flash.now[:alert] = t('conceptual_exams.new.current_discipline_does_not_have_conceptual_exam')
    end

    return if performed?

    @conceptual_exam = ConceptualExam.new(
      unity_id: current_unity.id,
      classroom_id: current_user_classroom.id,
      recorded_at: Date.current
    ).localized

    @conceptual_exam.assign_attributes(resource_params) if params[:conceptual_exam].present?

    authorize @conceptual_exam

    fetch_collections

    (@disciplines || []).each do |discipline|

      @conceptual_exam.conceptual_exam_values.build(
        conceptual_exam: @conceptual_exam,
        discipline: discipline
      )
    end

    mark_exempted_disciplines if @conceptual_exam.conceptual_exam_values.any?
  end

  def create
    begin
      set_options_by_user
      @conceptual_exam = find_or_initialize_conceptual_exam

      authorize @conceptual_exam

      only_one_conceptual_avaliation = GeneralConfiguration.annual_conceptual_evaluation?

      if only_one_conceptual_avaliation
        enrollment_classroom = StudentEnrollmentClassroom.by_classroom(resource_params[:classroom_id]).by_student(resource_params[:student_id]).first
        step = find_step_by_date(enrollment_classroom.joined_at)
        record_at = (enrollment_classroom.joined_at.to_date < step.start_at) ? step.start_at : enrollment_classroom.joined_at.to_date
      else
        step = steps_fetcher(@classroom).step_by_id(resource_params[:step_id])
        record_at = resource_params[:recorded_at].to_date
      end
      
      resource_params_changed = resource_params.merge!("step_id": step.id)
      resource_params_changed = resource_params_changed.merge!("step_number": step.step_number)
      resource_params_changed = resource_params_changed.merge!("recorded_at": record_at)

      @conceptual_exam.assign_attributes(resource_params_changed)
      @conceptual_exam.merge_conceptual_exam_values
      # @conceptual_exam.step_number = @conceptual_exam.step.try(:step_number)
      @conceptual_exam.teacher_id = current_teacher_id
      @conceptual_exam.current_user = current_user

      render :new and return unless @conceptual_exam.save!
      respond_to_save
    rescue ActiveRecord::RecordNotUnique
      Rails.logger.error("Ocorreu um erro ao salvar avaliação conceitual")
      retry
    rescue Exception => e
      Rails.logger.error(e.message)
      e.backtrace.each { |line| Rails.logger.error line }
    end
    return if performed?

    fetch_collections
    mark_not_existing_disciplines_as_invisible
    render :new
  end

  def update
    set_options_by_user
    @conceptual_exam = ConceptualExam.find(params[:id])
    @conceptual_exam.assign_attributes(resource_params)
    @conceptual_exam.teacher_id = current_teacher_id
    @conceptual_exam.current_user = current_user

    authorize @conceptual_exam

    if @conceptual_exam.save
      respond_to_save
    else
      set_options_by_user
      fetch_collections
      mark_not_existing_disciplines_as_invisible
      mark_persisted_disciplines_as_invisible if @conceptual_exam.conceptual_exam_values.any? { |value| value.new_record? }

      render :edit
    end
  end

  def destroy
    @conceptual_exam = ConceptualExam.find(params[:id]).localized
    @conceptual_exam.unity_id = @conceptual_exam.classroom.unity_id
    @classroom = @conceptual_exam.classroom
    @conceptual_exam.step_id = find_step_id
    @conceptual_exam.validation_type = :destroy

    allow_teacher_modify_prev_years

    authorize @conceptual_exam

    if @conceptual_exam.valid?
      ConceptualExamValue.by_conceptual_exam_id(@conceptual_exam.id)
                         .destroy_all

      @conceptual_exam.destroy unless ConceptualExamValue.by_conceptual_exam_id(@conceptual_exam.id).any?
    end

    respond_with @conceptual_exam, location: conceptual_exams_path
  end

  def history
    @conceptual_exam = ConceptualExam.find(params[:id]).localized

    authorize @conceptual_exam

    respond_with @conceptual_exam
  end

  def exempted_disciplines
    classroom = Classroom.find(params[:classroom_id])
    step = steps_fetcher(classroom).step_by_id(params[:step_id])
    student_enrollments = student_enrollments(step.start_at, step.end_at, classroom)

    exempted_disciplines = student_enrollments.find do |item|
      item[:student_id] == params[:student_id].to_i
    end.try(:exempted_disciplines)

    if exempted_disciplines
      render json: exempted_disciplines.try(:by_step_number, step.to_number)
    else
      render json: nil, :status => 422
    end
  end

  def find_conceptual_exam_by_student
    render json: find_conceptual_exam.try(:id)
  end

  def find_step_number_by_classroom
    classroom = Classroom.find(params[:classroom_id])
    step_numbers = StepsFetcher.new(classroom)&.steps
    steps = step_numbers.map { |step| { id: step.id, description: step.to_s, start_at: step.start_at, end_at: step.end_at } }

    render json: steps.to_json
  end

  def new_batch
    set_options_by_user
    @batch_form = ConceptualExamBatchForm.new(
      unity_id: current_unity.id,
      classroom_id: current_user_classroom.id,
      teacher_id: current_teacher_id,
      current_user: current_user
    )
    authorize ConceptualExam.new(classroom_id: current_user_classroom.id, student_id: nil)
  end

  def form_batch
    @batch_form = ConceptualExamBatchForm.new(batch_form_params)
    @batch_form.teacher_id = current_teacher_id
    @batch_form.current_user = current_user

    unless @batch_form.valid?
      set_options_by_user
      flash.now[:alert] = @batch_form.errors.full_messages.join('; ')
      return render :new_batch
    end

    @classroom = @batch_form.classroom
    @step = @batch_form.step
    @recorded_at = batch_last_date_of_step(@step)
    @batch_form.recorded_at = @recorded_at

    only_one = GeneralConfiguration.annual_conceptual_evaluation?
    if only_one
      # Na configuração "uma etapa só", step e recorded_at vêm do primeiro aluno; aqui usamos step_id do form
      @step = StepsFetcher.new(@classroom).step_by_id(@batch_form.step_id)
    end

    @student_enrollments = batch_student_enrollments(@classroom, @step)
    student_ids = @student_enrollments.map(&:student_id).uniq
    @students = Student.where(id: student_ids).ordered

    @disciplines_by_student = batch_disciplines_by_student(@classroom, @students, @step)
    @existing_by_student = batch_existing_conceptual_exams(@classroom, @step, student_ids)
    @all_discipline_ids = @disciplines_by_student.values.flatten.uniq
    @disciplines = Discipline.where(id: @all_discipline_ids).includes(:knowledge_area)
    @disciplines = @disciplines.to_a.sort_by { |d| [d.knowledge_area&.sequence.to_i, d.knowledge_area&.description.to_s, d.sequence.to_i, d.description] }

    @exempted_by_student = batch_exempted_by_student(@student_enrollments, @step)

    authorize ConceptualExam.new(classroom_id: @classroom.id, student_id: @students.first&.id)
    render :form_batch
  end

  def create_batch
    set_options_by_user
    @batch_form = ConceptualExamBatchForm.new(create_batch_params)
    @batch_form.teacher_id = current_teacher_id
    @batch_form.current_user = current_user

    unless @batch_form.valid?
      return redirect_to new_batch_conceptual_exams_path, alert: @batch_form.errors.full_messages.join('; ')
    end

    @classroom = @batch_form.classroom
    @step = @batch_form.step
    record_at = batch_valid_recorded_at(@step, @batch_form.recorded_at.to_date, @classroom)
    record_at = batch_last_date_of_step(@step) if record_at.blank?

    only_one = GeneralConfiguration.annual_conceptual_evaluation?
    saved = 0
    errors = []

    (@batch_form.students || {}).each do |student_id_str, disciplines_hash|
      begin
        student_id = student_id_str.to_i
        next if student_id.zero?

        values_by_discipline = (disciplines_hash || {}).reject { |_d, v| v.blank? }
        next if values_by_discipline.empty?

        if only_one
          enrollment = StudentEnrollmentClassroom.by_classroom(@classroom.id).by_student(student_id).first
          step = enrollment ? find_step_by_date(enrollment.joined_at) : @step
          record_at = step && (enrollment.joined_at.to_date < step.start_at) ? step.start_at : (enrollment&.joined_at&.to_date || record_at)
          record_at = batch_valid_recorded_at(step, record_at, @classroom) if step.present?
        else
          step = @step
        end

        values_by_discipline = filter_batch_values_by_teacher_disciplines(
          values_by_discipline, @classroom, step
        )
        next if values_by_discipline.empty?

        # Se já existir lançamento para este aluno nesta etapa, editar o existente.
        conceptual_exam = ConceptualExam.by_classroom(@classroom.id)
                                        .by_student_id(student_id)
                                        .by_step_number(step.step_number)
                                        .includes(:conceptual_exam_values)
                                        .first
        conceptual_exam ||= ConceptualExam.new(
          classroom_id: @classroom.id,
          student_id: student_id,
          recorded_at: record_at
        )
        conceptual_exam.unity_id = @classroom.unity_id
        conceptual_exam.step_id = step.id
        conceptual_exam.step_number = step.step_number
        conceptual_exam.recorded_at = record_at
        conceptual_exam.teacher_id = current_teacher_id
        conceptual_exam.current_user = current_user

        build_batch_conceptual_exam_values(conceptual_exam, values_by_discipline)
        conceptual_exam.merge_conceptual_exam_values

        authorize conceptual_exam
        if conceptual_exam.save
          saved += 1
        else
          errors << "#{Student.find_by(id: student_id)&.name}: #{conceptual_exam.errors.full_messages.join(', ')}"
        end
      rescue ActiveRecord::RecordNotUnique
        retry
      end
    end

    if errors.any?
      flash[:alert] = "Salvos: #{saved}. Erros: #{errors.join('; ')}"
    elsif saved.zero?
      flash[:alert] = I18n.t('conceptual_exams.create_batch.none_saved')
    else
      flash[:notice] = I18n.t('conceptual_exams.create_batch.saved', count: saved)
    end
    redirect_to conceptual_exams_path
  end

  def fetch_score_type
    return if params[:classroom_id].blank?

    classroom = Classroom.find(params[:classroom_id])

    discipline_score_types = (teacher_differentiated_discipline_score_types(classroom) +
    teacher_discipline_score_types(classroom)).uniq

    not_concept_score = discipline_score_types.none? { |discipline_score_type|
      discipline_score_type.eql?(ScoreTypes::CONCEPT)
    }

    render json: not_concept_score
  end

  def fetch_period
    return if params[:classroom_id].blank?

    render json: TeacherPeriodFetcher.new(
                    current_teacher.id,
                    params[:classroom_id],
                    current_user_discipline
                  ).teacher_period
  end

  private

  def view_data
    @conceptual_exam = ConceptualExam.find(params[:id]).localized
    @conceptual_exam.unity_id = @conceptual_exam.classroom.unity_id
    @classroom = @conceptual_exam.classroom
    @conceptual_exam.step_id = find_step_id

    authorize @conceptual_exam
    set_options_by_user
    fetch_collections
    add_missing_disciplines
    mark_not_assigned_disciplines_for_destruction
    mark_not_existing_disciplines_as_invisible
    mark_exempted_disciplines
  end

  def resource_params
    params.require(:conceptual_exam).permit(
      :unity_id,
      :classroom_id,
      :recorded_at,
      :student_id,
      :step_id,
      conceptual_exam_values_attributes: [
        :id,
        :discipline_id,
        :value,
        :exempted_discipline,
        :_destroy
      ]
    )
  end

  def find_step_id
    steps_fetcher(@classroom).step(@conceptual_exam.step_number).try(:id)
  end

  def find_step_by_date(date)
    step = steps_fetcher(@classroom).step_by_date(date)
    if step.blank?
      step = steps_fetcher(@classroom).steps.first
    end

    step
  end

  def find_conceptual_exam
    classroom = Classroom.find(resource_params[:classroom_id])

    ConceptualExam.by_classroom(resource_params[:classroom_id])
                  .by_student_id(resource_params[:student_id])
                  .by_step_id(classroom, resource_params[:step_id])
                  .first
  end

  def find_or_initialize_conceptual_exam
    conceptual_exam = find_conceptual_exam

    if conceptual_exam.blank?
      conceptual_exam = ConceptualExam.new(
        classroom_id: resource_params[:classroom_id],
        student_id: resource_params[:student_id],
        recorded_at: resource_params[:recorded_at],
        step_id: resource_params[:step_id]
      )
    end

    conceptual_exam
  end

  def add_missing_disciplines
    missing_disciplines.each do |missing_discipline|
      @conceptual_exam.conceptual_exam_values.build(
        conceptual_exam: @conceptual_exam,
        discipline: missing_discipline
      )
    end
  end

  def missing_disciplines
    missing_disciplines = []

    (@disciplines || []).each do |discipline|
      is_missing = @conceptual_exam.conceptual_exam_values.none? do |conceptual_exam_value|
        conceptual_exam_value.discipline.id == discipline.id
      end

      missing_disciplines << discipline if is_missing
    end

    missing_disciplines
  end

  def mark_not_assigned_disciplines_for_destruction
    @conceptual_exam.conceptual_exam_values.where.not(discipline_id: disciplines_with_assignment).each do |conceptual_exam_value|
      conceptual_exam_value.mark_for_destruction
    end
  end

  def mark_not_existing_disciplines_as_invisible
    teacher_discipline_ids = disciplines_with_assignment

    @conceptual_exam.conceptual_exam_values.each do |conceptual_exam_value|
      discipline_exists = if @disciplines.present?
        @disciplines.any? { |discipline| conceptual_exam_value.discipline.id == discipline.id }
      else
        teacher_discipline_ids.include?(conceptual_exam_value.discipline_id)
      end

      conceptual_exam_value.mark_as_invisible unless discipline_exists
    end
  end

  def mark_persisted_disciplines_as_invisible
    return if @disciplines.blank?

    @conceptual_exam.conceptual_exam_values.each do |conceptual_exam_value|
      discipline_exists = @disciplines.any? do |discipline|
        conceptual_exam_value.new_record?
      end

      conceptual_exam_value.mark_as_invisible unless discipline_exists
    end
  end

  def mark_exempted_disciplines
    return if @conceptual_exam.recorded_at.blank? || @conceptual_exam.step.blank?

    @student_enrollments ||= student_enrollments(
      @conceptual_exam.step.start_at,
      @conceptual_exam.step.end_at,
      @conceptual_exam.classroom,
      current_user_discipline
    )

    if current_student_enrollment = @student_enrollments.find { |item| item[:student_id] == @conceptual_exam.student_id }
      exempted_disciplines = current_student_enrollment.exempted_disciplines

      @conceptual_exam.conceptual_exam_values.each do |conceptual_exam_value|
        conceptual_exam_value.exempted_discipline = student_exempted_from_discipline?(conceptual_exam_value.discipline_id, exempted_disciplines)
      end
    end
  end

  def disciplines_with_assignment
    TeacherDisciplineClassroom.by_classroom(@conceptual_exam.classroom_id)
                              .by_teacher_id(current_teacher_id)
                              .by_year(current_school_calendar.year)
                              .pluck(:discipline_id)
                              .uniq
  end

  def fetch_collections
    if @conceptual_exam.step_id.present? && @conceptual_exam.student_id.present?
      fetch_unities_classrooms_disciplines_by_teacher
      fetch_students
    end
  end

  def fetch_unities_classrooms_disciplines_by_teacher
    return if @conceptual_exam.recorded_at.blank?

    fetcher = UnitiesClassroomsDisciplinesByTeacher.new(
      current_teacher.id,
      @conceptual_exam.classroom.unity_id,
      @conceptual_exam.classroom_id
    )
    fetcher.fetch!

    @disciplines = fetcher.disciplines
    @disciplines = @disciplines.by_score_type(ScoreTypes::CONCEPT, @conceptual_exam.try(:student_id)) if @disciplines.present?

    exempted_discipline_ids = ExemptedDisciplinesInStep.discipline_ids(
      @conceptual_exam.classroom_id,
      @conceptual_exam.step_number
    )

    @disciplines = @disciplines.not_grouper
    @disciplines = @disciplines.descriptor unless conceptual_exam_batch_layout?
    @disciplines = @disciplines.where.not(id: exempted_discipline_ids).where(id: disciplines_in_grade)
  end

  def disciplines_in_grade
    school_calendar = @conceptual_exam.school_calendar

    SchoolCalendarDisciplineGrade.where(
      school_calendar_id: school_calendar.id,
      grade_id: student_grade_id
    ).pluck(:discipline_id)
  end

  def student_grade_id
    ClassroomsGrade.by_student_id(@conceptual_exam.student_id)
                   .by_classroom_id(@conceptual_exam.classroom_id)
                   .first
                   .grade_id
  end

  def steps_fetcher(classroom)
    @steps_fetcher ||= StepsFetcher.new(classroom)
  end

  def student_enrollments(start_at, end_at, classroom = nil, discipline = current_user_discipline)
    classroom ||= @conceptual_exam.classroom
    @period = current_teacher_period(classroom) != Periods::FULL.to_i ? current_teacher_period(classroom) : nil

    StudentEnrollmentsList.new(
      classroom: classroom,
      discipline: discipline,
      start_at: start_at,
      end_at: end_at,
      score_type: StudentEnrollmentScoreTypeFilters::CONCEPT,
      search_type: :by_date_range,
      period: @period
    ).student_enrollments
  end

  def fetch_students
    @students = []

    if @conceptual_exam.classroom.present? && @conceptual_exam.recorded_at.present? && @conceptual_exam.step.present?
      @student_enrollments ||= student_enrollments(
        @conceptual_exam.step.start_at,
        @conceptual_exam.step.end_at,
        @conceptual_exam.classroom
      )

      if @conceptual_exam.student_id.present? &&
        @student_enrollments.find { |enrollment| enrollment[:student_id] == @conceptual_exam.student_id }.blank?
        @student_enrollments << StudentEnrollment.by_student(@conceptual_exam.student_id).first
      end

      @student_ids = @student_enrollments.collect(&:student_id)

      @students = Student.where(id: @student_ids).ordered
    end
  end

  def respond_to_save
    if params[:commit] == 'Salvar'
      respond_with @conceptual_exam, location: conceptual_exams_path
    else
      respond_with_next_conceptual_exam
    end
  end

  def respond_with_next_conceptual_exam
    next_conceptual_exam = fetch_next_conceptual_exam

    if next_conceptual_exam.present?
      if next_conceptual_exam.new_record?
        respond_with(
          @conceptual_exam,
          location: new_conceptual_exam_path(
            conceptual_exam: next_conceptual_exam.attributes.merge(step_id: @conceptual_exam.step_id)
          )
        )
      else
        respond_with(
          @conceptual_exam,
          location: edit_conceptual_exam_path(next_conceptual_exam)
        )
      end
    else
      respond_with(
        @conceptual_exam,
        location: new_conceptual_exam_path
      )
    end
  end

  def fetch_next_conceptual_exam
    next_student = fetch_next_student

    if next_student.present?
      next_conceptual_exam = ConceptualExam.find_or_initialize_by(
        classroom_id: @conceptual_exam.classroom_id,
        student_id: next_student.id,
        recorded_at: @conceptual_exam.recorded_at
      )
    end
  end

  def fetch_next_student
    @students = fetch_students

    if @students.present?
      next_student_index = @students.find_index(@conceptual_exam.student) + 1
      next_student_index = 0 if next_student_index == @students.length

      @students[next_student_index]
    end
  end

  def old_values
    return {} unless @conceptual_exam.classroom.present? && @conceptual_exam.student.present? && @conceptual_exam.step.present?

    @old_values ||= OldStepsConceptualValuesFetcher.new(@conceptual_exam.classroom, @conceptual_exam.student, @conceptual_exam.step).fetch
  end
  helper_method :old_values

  def student_exempted_from_discipline?(discipline_id, exempted_disciplines)
    exempted_disciplines.by_discipline(discipline_id)
                        .by_step_number(@conceptual_exam.step_number)
                        .any?
  end

  def current_teacher_period(classroom = nil)
    classroom ||= @conceptual_exam.classroom

    TeacherPeriodFetcher.new(
      current_teacher.id,
      classroom.id,
      current_user.current_discipline_id
    ).teacher_period
  end

  def set_options_by_user
    @classroom ||= current_user_classroom
    # if current_user.current_role_is_admin_or_employee?
      # @classrooms ||= [current_user_classroom]
      # @disciplines ||= [current_user_discipline]
    # else
      fetch_linked_by_teacher
    # end
  end

  def check_status_and_step(step_id, status)
    if step_id.present?
      @conceptual_exams = @conceptual_exams.by_step_id(@classroom, step_id)
      params[:filter][:by_step] = step_id
    end

    if status.present?
      @conceptual_exams = @conceptual_exams.by_status(@classrooms.to_a, current_teacher_id, status)
      params[:filter][:by_status] = status
    end
  end

  def fetch_conceptual_exams
    apply_scopes(ConceptualExam).includes(:student, :classroom)
                                .by_unity(current_unity)
                                .by_classroom(@classroom.id)
                                .by_teacher(current_teacher_id)
                                .ordered_by_date_and_student
  end

  def fetch_linked_by_teacher
    @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(current_teacher.id, current_unity, current_school_year)
    @classrooms = @fetch_linked_by_teacher[:classrooms].by_score_type(ScoreTypes::CONCEPT)
    @disciplines = @fetch_linked_by_teacher[:disciplines].by_score_type(ScoreTypes::CONCEPT)
  end

  def allow_teacher_modify_prev_years
    # create/update usam conceptual_exam; create_batch usa conceptual_exam_batch
    nested_params = params[:conceptual_exam].presence || params[:conceptual_exam_batch]
    @classroom ||= Classroom.find((nested_params || {})[:classroom_id])
    start_date = current_year_steps.first.start_date_for_posting
    end_date = current_year_steps.last.end_date_for_posting

    return if (start_date..end_date).cover?(Date.current)
    return if current_school_calendar&.opened_year && !GeneralConfiguration.block_modifications_after_last_step_ended?

    flash[:alert] = t('errors.general.not_allowed_to_modify_prev_years')
    redirect_to root_path
  end


  def current_year_steps
    @current_year_steps ||= begin
      steps = steps_fetcher(@classroom).steps if @classroom.present?
      year = current_school_year || current_school_calendar.year
      steps ||= SchoolCalendar.find_by(unity_id: current_unity.id, year: year).steps
      steps
    end
  end

  def conceptual_exam_batch_layout?
    GeneralConfiguration.conceptual_exam_batch_layout?
  end

  def require_batch_layout_enabled
    return if conceptual_exam_batch_layout?

    redirect_to conceptual_exams_path, alert: t('conceptual_exams.batch.not_available')
  end

  def batch_form_params
    params.fetch(:conceptual_exam_batch, {}).permit(:unity_id, :classroom_id, :step_id)
  end

  def create_batch_params
    p = params.require(:conceptual_exam_batch).permit(:unity_id, :classroom_id, :step_id, :recorded_at)
    # Strong Parameters não permite hashes aninhados com chaves dinâmicas (student_id => { discipline_id => value }).
    # Precisamos permitir o subtree students explicitamente.
    if params[:conceptual_exam_batch][:students].present?
      p[:students] = params[:conceptual_exam_batch][:students].permit!.to_h
    end
    p[:recorded_at] = p[:recorded_at].to_date if p[:recorded_at].present?
    p
  end

  # Última data da etapa (último dia letivo quando disponível, senão end_at).
  def batch_last_date_of_step(step)
    return nil if step.blank?

    if step.respond_to?(:school_day_dates) && step.school_day_dates.present?
      step.school_day_dates.last
    elsif step.respond_to?(:school_calendar_step_day?) && step.respond_to?(:start_at) && step.respond_to?(:end_at)
      range = (step.start_at.to_date..step.end_at.to_date).to_a
      range.reverse.find { |d| step.school_calendar_step_day?(d) } || step.end_at.to_date
    else
      step.end_at.to_date
    end
  end

  def batch_student_enrollments(classroom, step)
    # Mesma base do relatório: todos os alunos conceituais da turma na etapa, sem filtrar por período.
    StudentEnrollmentsList.new(
      classroom: classroom,
      discipline: current_user_discipline,
      start_at: step.start_at,
      end_at: step.end_at,
      score_type: StudentEnrollmentScoreTypeFilters::CONCEPT,
      search_type: :by_date_range,
      period: nil
    ).student_enrollments
  end

  def batch_discipline_ids_global(classroom, school_calendar, step)
    year = school_calendar.year
    teacher_discipline_ids = TeacherDisciplineClassroom
      .by_classroom(classroom.id)
      .by_teacher_id(current_teacher_id)
      .by_year(year)
      .pluck(:discipline_id)
      .uniq

    return [] if teacher_discipline_ids.blank?

    step_number = step.respond_to?(:to_number) ? step.to_number : step.step_number
    exempted_discipline_ids = ExemptedDisciplinesInStep.discipline_ids(classroom.id, step_number)
    discipline_scope = Discipline.by_score_type(ScoreTypes::CONCEPT).not_grouper
    discipline_scope = discipline_scope.descriptor unless conceptual_exam_batch_layout?

    discipline_scope
      .where(id: teacher_discipline_ids)
      .where.not(id: exempted_discipline_ids)
      .pluck(:id)
  end

  def batch_disciplines_by_student(classroom, students, step)
    school_calendar = SchoolCalendar.find_by(unity_id: classroom.unity_id, year: classroom.year)
    return {} if school_calendar.blank?

    discipline_ids_global = batch_discipline_ids_global(classroom, school_calendar, step)

    result = {}
    students.each do |student|
      cg = ClassroomsGrade.by_student_id(student.id).by_classroom_id(classroom.id).first
      next if cg.blank?

      grade_discipline_ids = SchoolCalendarDisciplineGrade
        .where(school_calendar_id: school_calendar.id, grade_id: cg.grade_id)
        .pluck(:discipline_id)
      result[student.id] = discipline_ids_global & grade_discipline_ids
    end
    result
  end

  def filter_batch_values_by_teacher_disciplines(values_by_discipline, classroom, step)
    school_calendar = SchoolCalendar.find_by(unity_id: classroom.unity_id, year: classroom.year)
    return {} if school_calendar.blank?

    allowed_ids = batch_discipline_ids_global(classroom, school_calendar, step)
    values_by_discipline.select { |discipline_id, _| allowed_ids.include?(discipline_id.to_i) }
  end

  def batch_exempted_by_student(student_enrollments, step)
    result = {}
    step_number = step.respond_to?(:to_number) ? step.to_number : step.step_number
    student_enrollments.each do |enrollment|
      exempted = enrollment.exempted_disciplines&.by_step_number(step_number)
      result[enrollment.student_id] = exempted ? exempted.pluck(:discipline_id) : []
    end
    result
  end

  def batch_existing_conceptual_exams(classroom, step, student_ids)
    ConceptualExam
      .by_classroom(classroom.id)
      .by_step_number(step.step_number)
      .where(student_id: student_ids)
      .includes(:conceptual_exam_values)
      .index_by(&:student_id)
  end

  # Retorna uma data que seja dia letivo da etapa (para passar na validação do ConceptualExam).
  def batch_valid_recorded_at(step, date, classroom)
    return date if date.blank? || step.blank?

    date = date.to_date
    if step.respond_to?(:school_calendar_step_day?) && step.school_calendar_step_day?(date)
      return date
    end
    step.respond_to?(:first_school_calendar_date) ? step.first_school_calendar_date : date
  end

  def build_batch_conceptual_exam_values(conceptual_exam, values_by_discipline)
    values_by_discipline.each do |discipline_id, value|
      discipline_id = discipline_id.to_i
      next if discipline_id.zero?

      existing_value = conceptual_exam.conceptual_exam_values.find { |v| v.discipline_id == discipline_id }

      if value.blank?
        existing_value&.mark_for_destruction
        next
      end

      if existing_value
        existing_value.value = value
      else
        conceptual_exam.conceptual_exam_values.build(
          discipline_id: discipline_id,
          value: value
        )
      end
    end
  end
end
