class DailyFrequenciesController < ApplicationController
  before_action :require_current_classroom
  before_action :require_teacher
  before_action :set_number_of_classes, only: [:new, :form, :create, :edit_multiple]
  before_action :require_allow_to_modify_prev_years, only: [:create, :destroy_multiple]
  before_action :require_valid_daily_frequency_classroom
  before_action :require_profile_discipline_linked_to_classroom!, only: [:create, :create_or_update_multiple]

  def new
    @daily_frequency = DailyFrequency.new.localized
    @daily_frequency.unity = current_unity
    @daily_frequency.classroom = current_user_classroom
    @daily_frequency.discipline = current_user_discipline
    @daily_frequency.frequency_date = Time.zone.today

    set_options_by_user

    @period = @admin_or_teacher ? current_teacher_period : set_options_by_classroom
    @class_numbers = []

    authorize @daily_frequency
  end

  def form
    redirect_to edit_multiple_daily_frequencies_path(
      daily_frequency: {
        unity_id: params[:unity_id],
        classroom_id: params[:classroom_id],
        frequency_date: params[:frequency_date],
        discipline_id: params[:discipline_id],
        period: params[:period]
      },
      class_numbers: params[:class_numbers].split(',').sort
    )
  end

  def class_numbers_by_discipline
    classroom_id = params[:classroom_id].presence
    discipline_id = params[:discipline_id].presence
    frequency_date = parse_frequency_date(params[:frequency_date])

    if classroom_id.blank? || discipline_id.blank? || frequency_date.blank?
      render json: []
      return
    end

    weekday = frequency_date.strftime("%A").downcase
    # Mesma regra do select de disciplinas: aulas do dia no quadro, sem filtrar por turno.
    allocations = LessonsBoardLessonWeekday.includes(lessons_board_lesson: :lessons_board)
                                           .by_classroom(classroom_id)
                                           .by_teacher(current_teacher.id)
                                           .by_discipline(discipline_id)
                                           .by_weekday(weekday)
                                           .order('lessons_board_lessons.lesson_number')

    class_numbers = allocations.map { |allocation|
      allocation.lessons_board_lesson&.lesson_number&.to_i
    }.compact.uniq.sort

    period = infer_daily_frequency_period_from_allocations(
      allocations,
      classroom_id: classroom_id,
      discipline_id: discipline_id
    )

    render json: { class_numbers: class_numbers, period: period }
  end

  def disciplines_for_frequency_date
    classroom_id = params[:classroom_id].presence
    frequency_date = parse_frequency_date(params[:frequency_date])

    if classroom_id.blank? || frequency_date.blank?
      render_disciplines_for_frequency_json([])
      return
    end

    authorize DailyFrequency.new, :new?

    classroom = Classroom.find_by(id: classroom_id)
    if classroom.blank?
      render_disciplines_for_frequency_json([])
      return
    end

    disciplines = disciplines_for_classroom_and_frequency(
      classroom: classroom,
      frequency_date: frequency_date
    )

    render_disciplines_for_frequency_json(
      disciplines.map { |d| { id: d.id, description: d.description } }
    )
  end

  def fetch_frequency_type
    classroom_id = params[:classroom_id].presence
    discipline_id = params[:discipline_id].presence || current_user.current_discipline_id

    return render json: FrequencyTypes::GENERAL if classroom_id.blank? || discipline_id.blank?

    classroom = Classroom.find_by(id: classroom_id)
    return render json: FrequencyTypes::GENERAL if classroom.blank?
    render json: frequency_type_for_classroom_and_discipline(
      classroom: classroom,
      discipline_id: discipline_id
    )
  end

  def create
    @daily_frequency = DailyFrequency.new(daily_frequency_params)
    @daily_frequency.school_calendar = current_school_calendar
    @daily_frequency.teacher_id = current_teacher_id
    @class_numbers = parsed_class_numbers_from_request
    @discipline = params.dig(:daily_frequency, :discipline_id).presence

    set_options_by_user

    apply_frequency_type_to_daily_frequency!

    @period = @admin_or_teacher ? params[:daily_frequency][:period] : set_options_by_classroom

    if @daily_frequency.valid?
      @frequency_type = current_frequency_type(@daily_frequency)

      return if @frequency_type == FrequencyTypes::BY_DISCIPLINE && !(validate_class_numbers && validate_discipline)

      if teacher_absence_blocks_frequency?(@daily_frequency, @class_numbers)
        redirect_to new_daily_frequency_path, alert: I18n.t('daily_frequencies.create.blocked_by_teacher_absence')
        return
      end

      redirect_to edit_multiple_daily_frequencies_path(
        daily_frequency: daily_frequency_params_for_redirect,
        class_numbers: @class_numbers
      )
    else

      # Verifica se já existe frequência salva para essa data, mesmo que não seja dia letivo
      # Se existir, redireciona para edit_multiple para permitir exclusão
      if existing_frequencies_for_date?
        @frequency_type = current_frequency_type(@daily_frequency)

        return if @frequency_type == FrequencyTypes::BY_DISCIPLINE && !(validate_class_numbers && validate_discipline)

        if teacher_absence_blocks_frequency?(@daily_frequency, @class_numbers)
          redirect_to new_daily_frequency_path, alert: I18n.t('daily_frequencies.create.blocked_by_teacher_absence')
          return
        end

        redirect_to edit_multiple_daily_frequencies_path(
          daily_frequency: daily_frequency_params_for_redirect,
          class_numbers: @class_numbers
        )
        return
      end

      render :new
    end
  end

  def edit_multiple
    @daily_frequencies = find_or_initialize_daily_frequencies(params[:class_numbers])
      .sort { |a, b| a.class_number <=> b.class_number }
    @daily_frequency = @daily_frequencies.first

    set_options_by_user
    @teacher_absence_blocks_date = teacher_absence_blocks_frequency?(
      @daily_frequency,
      params[:class_numbers].to_s.split(',').map(&:strip)
    )
    @period = @admin_or_teacher ? current_teacher_period : set_options_by_classroom

    # Em turma de turno integral (FULL), manter o período real do professor (matutino/vespertino)
    # para filtrar faltas justificadas e matrículas por turno. Evita que falta justificada da
    # manhã apareça no registro da tarde (e vice-versa).
    @period = nil if @period == Periods::FULL.to_i && !current_teacher_has_specific_period?

    @general_configuration = GeneralConfiguration.current

    fetch_disciplines_by_day

    authorize @daily_frequency

    @students = []
    @students_list_marked_as_read = []
    @any_exempted_from_discipline = false
    @any_inactive_student = false
    @any_in_active_search = false
    @dependence_students = false
    @absence_justification = AbsenceJustification.new
    @absence_justification.school_calendar = current_school_calendar

    student_enrollment_ids = fetch_enrollment_classrooms.map { |student_enrollment|
      student_enrollment[:student_enrollment_id]
    }

    student_ids = fetch_enrollment_classrooms.map { |student_enrollment|
      student_enrollment[:student].id
    }

    step = @daily_frequency.school_calendar.step(@daily_frequency.frequency_date).try(:to_number)
    discipline = @daily_frequency.discipline
    frequency_date = @daily_frequency.frequency_date

    dependencies = StudentsInDependency.call(student_enrollments: student_enrollment_ids, disciplines: discipline)
    exempt = StudentsExemptFromDiscipline.call(student_enrollments: student_enrollment_ids, discipline: discipline, step: step)
    active = ActiveStudentsOnDate.call(student_enrollments: student_enrollment_ids, date: frequency_date, classroom_id: @daily_frequency.classroom_id)
    active_search = in_active_searches(student_enrollment_ids, @daily_frequency.frequency_date)
    absence_justifications = AbsenceJustifiedOnDate.call(
      students: student_ids,
      date: frequency_date,
      end_date: frequency_date,
      classroom: @daily_frequency.classroom_id,
      period: @period,
      class_numbers: @daily_frequencies.map(&:class_number).compact
    )

    @students_as_justified = []

    # Agrupar enrollment_classrooms por student_id para selecionar apenas a matrícula mais recente
    enrollment_classrooms_by_student = fetch_enrollment_classrooms.group_by { |ec| ec[:student].id }
    frequency_date = @daily_frequency.frequency_date.to_date
    
    enrollment_classrooms_by_student.each do |student_id, enrollment_classrooms|
      # Selecionar a matrícula mais recente baseada no sequence e joined_at
      # Prioriza sequence (maior = mais recente), depois joined_at (mais recente = mais recente)
      enrollment_classroom = enrollment_classrooms.max_by do |ec|
        # Acessar sequence e joined_at do hash
        sequence = ec[:sequence]
        joined_at = ec[:joined_at]
        
        # Converter sequence para inteiro e joined_at para Date
        sequence_value = sequence.to_i rescue 0
        joined_at_date = joined_at.is_a?(Date) ? joined_at : (joined_at.to_date rescue nil)
        
        # Retorna um array para comparação: [sequence, joined_at]
        # O max_by vai comparar primeiro pelo sequence, depois pelo joined_at
        [joined_at_date, sequence_value || Date.new(1900, 1, 1)]
      end
      
      student = enrollment_classroom[:student]
      student_enrollment = enrollment_classroom[:student_enrollment]
      left_at = enrollment_classroom[:left_at]
      joined_at = enrollment_classroom[:joined_at]
      
      student_enrollment_id = enrollment_classroom[:student_enrollment_id]
      
      # Verificar se o aluno está ativo na data da frequência
      # Considera: joined_at <= frequency_date E (left_at é nulo OU left_at > frequency_date)
      joined_at_date = joined_at.to_date rescue nil
      left_at_date = left_at.to_date rescue nil if left_at.present?
      
      is_active_on_frequency_date = false
      if joined_at_date && joined_at_date <= frequency_date
        is_active_on_frequency_date = left_at_date.nil? || left_at_date.blank? || left_at_date > frequency_date
      end
      
      # O aluno está ativo se está no hash 'active' (calculado pelo ActiveStudentsOnDate)
      # E está realmente ativo na data (verificação manual)
      activated_student = active.include?(enrollment_classroom[:student_enrollment_classroom_id]) && is_active_on_frequency_date
      has_dependence = dependencies[student_enrollment_id] ? true : false
      has_exempted = exempt[student_enrollment_id] ? true : false
      
      if absence_justifications[student.id]
        absence_justification = absence_justifications[student.id]
        @students_as_justified << student        
      else
        absence_justification = {}
      end
      
      in_active_search = active_search[@daily_frequency.frequency_date]&.include?(student_enrollment_id)
      sequence = enrollment_classroom[:sequence] if show_inactive_enrollments

      @any_exempted_from_discipline ||= has_exempted
      @any_in_active_search ||= in_active_search
      @dependence_students ||= has_dependence
      @any_inactive_student ||= !activated_student

      next unless activated_student || show_inactive_enrollments
      
      @students << {
        student: student,
        dependence: has_dependence,
        active: activated_student,
        exempted_from_discipline: has_exempted,
        in_active_search: in_active_search,
        absence_justification: absence_justification,
        sequence: sequence,
        joined_at: joined_at,
        left_at: left_at
      }

    end

    all_inactive = @students.all? { |element| element[:active] == false }

    if @students.blank? || all_inactive
      flash.now[:warning] = t('.warning_no_students')

      render :new

      return
    end

    build_daily_frequency_students
    mark_for_destruction_not_existing_students

    @students = @students.sort_by { |student| student[:sequence].to_i } if show_inactive_enrollments
  end

  def create_or_update_multiple
    begin
      daily_frequency_record = nil
      daily_frequency_attributes = daily_frequency_params
      daily_frequencies_attributes = daily_frequencies_params

      frequency_for_check = DailyFrequency.new(daily_frequency_attributes)
      if teacher_absence_blocks_frequency?(frequency_for_check, class_numbers_from_params)
        redirect_to new_daily_frequency_path, alert: I18n.t('daily_frequencies.create.blocked_by_teacher_absence')
        return
      end

      receive_email_confirmation = ActiveRecord::Type::Boolean.new.cast(
        params[:daily_frequency][:receive_email_confirmation]
      )

      edit_multiple_daily_frequencies_path = edit_multiple_daily_frequencies_path(
        daily_frequency: daily_frequency_attributes.slice(
          :classroom_id,
          :discipline_id,
          :frequency_date,
          :period,
          :unity_id
        ),
        class_numbers: class_numbers_from_params,
        anchor: 'bottom'
      )

      ActiveRecord::Base.transaction do
        daily_frequencies_attributes.each_value do |daily_frequency_students_params|

          daily_frequency_students_params[:students_attributes].delete_if do |_, daily_frequency_student|
            daily_frequency_student[:absence_justification_student_id].to_i.eql?(-2)
          end
          
          daily_frequency_attribute_normalizer = DailyFrequencyAttributesNormalizer.new(
            daily_frequency_students_params,
            daily_frequency_attributes
          )
          daily_frequency_attribute_normalizer.normalize_daily_frequency!

          daily_frequency_record = find_or_initialize_daily_frequency_by(daily_frequency_attributes)
          daily_frequency_attribute_normalizer.normalize_daily_frequency_students!(
            daily_frequency_record,
            daily_frequency_students_params
          )

          daily_frequency_students_params[:students_attributes].each_value do |daily_frequency_student|
            next unless daily_frequency_student[:absence_justification_student_id].to_i.eql?(-1)

            params = {
              student_ids: [daily_frequency_student[:student_id]],
              absence_date: daily_frequency_attributes[:frequency_date],
              justification: nil,
              absence_date_end: daily_frequency_attributes[:frequency_date],
              unity_id: daily_frequency_attributes[:unity_id],
              classroom_id: daily_frequency_attributes[:classroom_id],
              class_number: daily_frequency_students_params[:class_number]
            }

            absence_justification = AbsenceJustification.new(params)
            absence_justification.teacher = current_teacher
            absence_justification.user = current_user
            absence_justification.school_calendar = current_school_calendar
            absence_justification.period = daily_frequency_attributes[:period]

            absence_justification.save

            daily_frequency_student[:absence_justification_student_id] = absence_justification.absence_justifications_students.first.id
          end
          daily_frequency_record.assign_attributes(daily_frequency_students_params)

          daily_frequency_record.save!
        end
      end
    rescue ActiveRecord::RecordNotUnique
      retry
    rescue ActiveRecord::RecordInvalid => e
      flash[:error] = e.message
      return redirect_to new_daily_frequency_path
    end

    flash[:success] = t('.daily_frequency_success')

    UniqueDailyFrequencyStudentsCreator.call_worker(
      current_entity.id,
      daily_frequency_record.classroom_id,
      daily_frequency_record.frequency_date,
      current_teacher_id
    )

    if receive_email_confirmation
      ReceiptMailer.delay.notify_daily_frequency_success(
        current_user.first_name,
        current_user.email,
        "#{request.base_url}#{edit_multiple_daily_frequencies_path}",
        daily_frequency_attributes[:frequency_date].to_date.strftime('%d/%m/%Y'),
        daily_frequency_record.classroom.description,
        daily_frequency_record.unity.name
      )
    end

    redirect_to edit_multiple_daily_frequencies_path
  end

  def destroy_multiple
    @daily_frequencies = DailyFrequency.where(id: params[:daily_frequencies_ids])

    if @daily_frequencies.any?
      daily_frequency = @daily_frequencies.first
      classroom_id = daily_frequency.classroom_id
      frequency_date = daily_frequency.frequency_date

      authorize daily_frequency

      @daily_frequencies.each(&:destroy)

      UniqueDailyFrequencyStudentsCreator.call_worker(
        current_entity.id,
        classroom_id,
        frequency_date,
        current_teacher_id
      )

      respond_with @daily_frequencies.first, location: new_daily_frequency_path
    else
      flash[:alert] = t('.alert')

      redirect_to new_daily_frequency_path
    end
  end

  def history
    @daily_frequency = DailyFrequency.find(params[:id])

    authorize @daily_frequency

    respond_with @daily_frequency
  end

  def history_multiple
    @daily_frequencies = DailyFrequency.where(id: params[:daily_frequencies_ids])

    respond_with @daily_frequencies
  end

  private

  # JSON array literal — evita ActiveModel::Serializers envolver em { daily_frequencies: ... }.
  def render_disciplines_for_frequency_json(payload)
    render plain: payload.to_json, content_type: 'application/json'
  end

  # Turma do formulário (params) ou do registro em edição — evita usar só a turma da sessão,
  # que pode divergir e montar o quadro de aulas do dia com a turma errada (sem aulas "hoje").
  def resolved_classroom_id_for_lessons_board
    cid = params.dig(:daily_frequency, :classroom_id).presence
    cid = cid.to_i if cid.present?
    return cid if cid.present? && cid.positive?

    @daily_frequency&.classroom_id.presence || current_user_classroom&.id
  end

  def daily_frequency_params
    params.require(:daily_frequency).permit(
      :unity_id, :classroom_id, :frequency_date, :discipline_id, :period
    )
  end

  def daily_frequency_params_for_redirect
    attrs = daily_frequency_params.to_h.stringify_keys
    if current_frequency_type(@daily_frequency) == FrequencyTypes::GENERAL
      attrs['discipline_id'] = nil
    end
    attrs
  end

  def daily_frequencies_params
    params.require(:daily_frequency).permit(
      daily_frequencies: [
        :class_number,
        students_attributes: [
          [:id, :daily_frequency_id, :student_id, :present, :dependence, :active, :type_of_teaching, :absence_justification_student_id]
        ]
      ]
    ).require(:daily_frequencies)
  end

  def current_frequency_type(daily_frequency)
    discipline_id = daily_frequency.discipline_id.presence ||
                    params.dig(:daily_frequency, :discipline_id).presence ||
                    @discipline

    frequency_type_for_classroom_and_discipline(
      classroom: daily_frequency.classroom,
      discipline_id: discipline_id
    )
  end

  def validate_class_numbers
    return true if @class_numbers.present?

    @error_on_class_numbers = true
    flash.now[:alert] = t('errors.daily_frequencies.class_numbers_required_when_not_global_absence')

    false
  end

  def validate_discipline
    return true if @discipline.present?

    @error_on_discipline = true
    flash.now[:alert] = t('errors.daily_frequencies.discipline_required_when_not_global_absence')

    false
  end

  def require_profile_discipline_linked_to_classroom!
    classroom = frequency_classroom_for_link_validation
    return if classroom.blank?

    discipline_id = frequency_discipline_id_for_link_validation(classroom)
    return if discipline_id.blank?

    linked = TeacherClassroomAndDisciplineFetcher.fetch!(
      current_teacher.id,
      current_unity,
      current_school_year,
      classroom
    )
    linked_discipline_ids = (linked[:disciplines] || []).map(&:id)
    return if linked_discipline_ids.include?(discipline_id)

    flash[:alert] = t('errors.daily_frequencies.discipline_not_linked_to_classroom')
    redirect_to new_daily_frequency_path
  end

  def find_or_initialize_daily_frequencies(class_numbers)
    return find_or_initialize_discipline_frequencies(class_numbers) if class_numbers?(class_numbers)

    find_or_initialize_global_frequencies
  end

  def find_or_initialize_global_frequencies
    params = daily_frequency_params
    params[:discipline_id] = nil
    params[:class_number] = nil
    params[:period] = current_teacher_period if params[:period].blank? && current_teacher_has_specific_period?

    [find_or_initialize_daily_frequency_by(params)]
  end

  def find_or_initialize_discipline_frequencies(class_numbers)
    daily_frequencies = []

    class_numbers.each do |class_number|
      params = daily_frequency_params
      params[:class_number] = class_number
      # Em turma integral, garantir período do professor na busca para não reutilizar registro de outro turno
      params[:period] = current_teacher_period if params[:period].blank? && current_teacher_has_specific_period?

      daily_frequencies << find_or_initialize_daily_frequency_by(params)
    end

    daily_frequencies
  end

  def find_or_initialize_daily_frequency_by(params)
    daily_frequency = DailyFrequency.find_or_initialize_by(
      params.slice(
        :classroom_id,
        :frequency_date,
        :discipline_id,
        :class_number,
        :period
      )
    ).tap do |daily_frequency_record|
      daily_frequency_record.unity_id = params[:unity_id]
      daily_frequency_record.school_calendar_id = current_school_calendar.id
      daily_frequency_record.owner_teacher_id = daily_frequency_record.teacher_id = current_teacher_id
      daily_frequency_record.origin = OriginTypes::WEB
    end

    @new_record ||= daily_frequency.new_record?

    daily_frequency
  end

  def current_teacher_period
    TeacherPeriodFetcher.new(
      current_teacher.id,
      current_user.current_classroom_id,
      current_user.current_discipline_id
    ).teacher_period
  end

  # Em turma integral, o professor pode ter período específico (matutino/vespertino) na alocação.
  # Retorna true nesse caso, para que filtros (falta justificada, matrículas) usem o turno correto.
  def current_teacher_has_specific_period?
    period = current_teacher_period
    period.present? && period != Periods::FULL.to_i
  end

  def current_teacher_period_by_classroom(classroom, discipline)
    TeacherPeriodFetcher.new(
      current_teacher.id,
      classroom,
      discipline
    ).teacher_period
  end

  def frequency_classroom_for_link_validation
    classroom_id =
      params.dig(:daily_frequency, :classroom_id).presence ||
      params.dig(:frequency_in_batch_form, :classroom_id).presence ||
      current_user.current_classroom_id

    return if classroom_id.blank?

    Classroom.find_by(id: classroom_id)
  end

  def frequency_discipline_id_for_link_validation(classroom)
    selected_discipline_id = params.dig(:daily_frequency, :discipline_id).presence&.to_i
    profile_discipline_id = current_user.current_discipline_id

    # Quando o professor escolhe uma disciplina no formulário, o vínculo validado
    # precisa ser exatamente o da disciplina selecionada.
    return selected_discipline_id if selected_discipline_id.present?

    effective_discipline_id = selected_discipline_id || profile_discipline_id
    frequency_type = frequency_type_for_classroom_and_discipline(
      classroom: classroom,
      discipline_id: effective_discipline_id
    )

    if frequency_type == FrequencyTypes::GENERAL
      profile_discipline_id
    else
      selected_discipline_id || profile_discipline_id
    end
  end

  def frequency_type_for_classroom_and_discipline(classroom:, discipline_id:)
    return FrequencyTypes::GENERAL if classroom.blank?

    exam_rule_frequency_type = classroom.classrooms_grades
                                      .first
                                      &.exam_rule
                                      &.frequency_type
    return FrequencyTypes::BY_DISCIPLINE if exam_rule_frequency_type == FrequencyTypes::BY_DISCIPLINE

    discipline_id = discipline_id.presence || current_user.current_discipline_id
    return FrequencyTypes::GENERAL if discipline_id.blank?

    grade_ids = classroom.classrooms_grades.pluck(:grade_id)
    linked_by_discipline = TeacherDisciplineClassroom.where(
      teacher_id: current_teacher.id,
      classroom_id: classroom.id,
      discipline_id: discipline_id,
      year: classroom.year,
      grade_id: grade_ids,
      allow_absence_by_discipline: 1,
      active: true
    ).exists?

    linked_by_discipline ? FrequencyTypes::BY_DISCIPLINE : FrequencyTypes::GENERAL
  end

  def build_daily_frequency_students
    @daily_frequencies.each do |daily_frequency|
      current_student_ids = daily_frequency.students.map(&:student_id)

      @students.each do |student|
        next if student[:exempted_from_discipline]
        next if current_student_ids.any? { |student_id| student_id == student[:student].id }

        daily_frequency.students.build(
          student_id: student[:student].id,
          dependence: student[:dependence],
          present: true,
          active: student[:active]
        )
      end
    end
  end

  def mark_for_destruction_not_existing_students
    current_student_ids = @students.map { |student| student[:student].id }

    @daily_frequencies.each do |daily_frequency|
      daily_frequency_students = daily_frequency.students.reject { |daily_frequency_student|
        current_student_ids.include?(daily_frequency_student.student_id)
      }

      daily_frequency_students.each(&:mark_for_destruction)
    end
  end

  def fetch_enrollment_classrooms
    list ||= StudentEnrollmentsList.new(
                classroom: @daily_frequency.classroom,
                grade: discipline_classroom_grade_ids,
                discipline: @daily_frequency.discipline,
                date: @daily_frequency.frequency_date,
                search_type: :by_date,
                period: @period
              ).student_enrollment_classrooms    
  end

  def set_number_of_classes
    @number_of_classes = current_school_calendar.number_of_classes
  end

  def require_teacher
    return if current_teacher.present?

    flash[:alert] = t('errors.daily_frequencies.require_teacher')
    redirect_to root_path
  end

  def in_active_searches(student_enrollment_ids, frequency_date)
    @in_active_searches ||= ActiveSearch.new.enrollments_in_active_search?(student_enrollment_ids, frequency_date)
  end

  def class_numbers_from_params
    daily_frequencies_params.map { |daily_frequency_students_params|
      daily_frequency_students_params.second[:class_number].presence
    }.compact
  end

  def class_numbers?(class_numbers)
    return false if class_numbers.blank?

    class_numbers = (class_numbers - [0, '0', '', nil, '[]'])
    class_numbers.present?
  end

  def require_valid_daily_frequency_classroom
    return unless current_user.current_role_is_admin_or_employee?
    return unless params[:daily_frequency]
    return unless params[:daily_frequency][:classroom_id]
    return if current_user.current_classroom_id == params[:daily_frequency][:classroom_id].to_i

    redirect_to new_daily_frequency_path
  end

  def discipline_classroom_grade_ids
    classroom_grade_ids = ClassroomsGrade.by_classroom_id(@daily_frequency.classroom.id).pluck(:grade_id)
    school_calendar = StepsFetcher.new(@daily_frequency.classroom).school_calendar

    if @frequency_type == FrequencyTypes::BY_DISCIPLINE
      SchoolCalendarDisciplineGrade.where(
        grade_id: classroom_grade_ids,
        school_calendar_id: school_calendar.id,
        discipline_id: @daily_frequency.discipline.id
      ).pluck(:grade_id)
    else
      SchoolCalendarDisciplineGrade.where(
        grade_id: classroom_grade_ids,
        school_calendar_id: school_calendar.id
      ).pluck(:grade_id)
    end
  end

  def show_inactive_enrollments
    @show_inactive_enrollments ||= GeneralConfiguration.first.show_inactive_enrollments
  end

  def set_options_by_classroom
    classroom = @daily_frequency.classroom
    discipline = @daily_frequency.discipline

    @period = current_teacher_period_by_classroom(classroom, discipline)
    @daily_frequency.period = @period
  end

  def set_options_by_user
    @classrooms ||= [current_user_classroom]
    @period = current_teacher_period
    fetch_linked_by_teacher
  end

  def fetch_linked_by_teacher
    @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(current_teacher.id, current_unity, current_school_year, current_user_classroom)
    @classrooms ||= @fetch_linked_by_teacher[:classrooms]

    if params[:discipline_id].present?
      @disciplines ||= [current_user_discipline]
    elsif (ctx = discipline_options_context)
      @disciplines = disciplines_for_classroom_and_frequency(
        classroom: ctx[:classroom],
        frequency_date: ctx[:date]
      )
    else
      @disciplines = (@fetch_linked_by_teacher[:disciplines] || []).select { |d| d.grouper == false && d.descriptor == false }
      schedule_ids = fetch_disciplines_by_day
      @disciplines = @disciplines.select { |d| schedule_ids.include?(d.id) } if schedule_ids.present?
    end

    @disciplines = (@disciplines || []).select { |d| d.grouper == false && d.descriptor == false }

    @daily_schedule_discipline ||= fetch_disciplines_by_day

    linked_disciplines = (@fetch_linked_by_teacher[:disciplines] || []).select { |d| d.grouper == false && d.descriptor == false }
    @disciplines_for_content = if @daily_schedule_discipline.present?
                                 linked_disciplines.select { |d| @daily_schedule_discipline.include?(d.id) }
                               else
                                 linked_disciplines
                               end
    @disciplines_for_content = filter_disciplines_for_content_registration(
      @disciplines_for_content,
      current_user_classroom
    )

    @knowledge_areas_for_content = if is_multigrade_infantil_fundamental?
                                     filter_knowledge_areas_for_content_registration(
                                       KnowledgeArea.by_teacher(current_teacher)
                                                    .by_classroom_id(current_user_classroom.id)
                                                    .ordered,
                                       current_user_classroom
                                     )
                                   else
                                     @disciplines_for_content.map(&:knowledge_area).compact.uniq(&:id)
                                   end
    @knowledge_areas = []
    @knowledge_areas = [@disciplines.first&.knowledge_area] if @disciplines.first&.knowledge_area.present?
  end

  def discipline_options_context
    classroom_id = resolved_classroom_id_for_lessons_board
    return nil if classroom_id.blank?

    classroom = Classroom.find_by(id: classroom_id)
    return nil unless classroom

    date = parse_frequency_date(params.dig(:daily_frequency, :frequency_date))
    date ||= @daily_frequency&.frequency_date&.to_date
    return nil if date.blank?

    { classroom: classroom, date: date }
  end

  def disciplines_for_classroom_and_frequency(classroom:, frequency_date:)
    linked = TeacherClassroomAndDisciplineFetcher.fetch!(
      current_teacher.id,
      current_unity,
      current_school_year,
      classroom
    )
    disciplines = (linked[:disciplines] || []).select { |d| d.grouper == false && d.descriptor == false }
    disciplines = filter_disciplines_for_teacher_frequency_type(
      disciplines: disciplines,
      classroom: classroom
    )

    return disciplines if classroom_without_lessons_board?(classroom.id)

    # Disciplinas do dia pela grade (dia da semana), sem filtrar por turno — o professor
    # vê tudo que está no quadro daquele dia na turma.
    schedule_ids = schedule_discipline_ids_for_classroom_weekday(
      classroom_id: classroom.id,
      date: frequency_date,
      period: nil
    )
    return disciplines if schedule_ids.blank?

    disciplines.select { |d| schedule_ids.include?(d.id) }
  end

  def filter_disciplines_for_teacher_frequency_type(disciplines:, classroom:)
    return disciplines if disciplines.blank?

    exam_rule_frequency_type = classroom.classrooms_grades
                                  .first
                                  &.exam_rule
                                  &.frequency_type
    return disciplines if exam_rule_frequency_type == FrequencyTypes::BY_DISCIPLINE

    grade_ids = classroom.classrooms_grades.pluck(:grade_id)
    allowed_discipline_ids = TeacherDisciplineClassroom.where(
      teacher_id: current_teacher.id,
      classroom_id: classroom.id,
      year: classroom.year,
      grade_id: grade_ids,
      allow_absence_by_discipline: 1,
      active: true
    ).pluck(:discipline_id).uniq

    disciplines.select { |discipline| allowed_discipline_ids.include?(discipline.id) }
  end

  def classroom_without_lessons_board?(classroom_id)
    !LessonsBoard.joins(:classrooms_grade)
                 .where(classrooms_grades: { classroom_id: classroom_id })
                 .exists?
  end

  def schedule_discipline_ids_for_classroom_weekday(classroom_id:, date:, period: nil)
    weekday = date.strftime("%A").downcase
    scope = LessonsBoardLessonWeekday.by_classroom(classroom_id).by_weekday(weekday)
    scope = scope.by_period(period) if period.present?
    scope.includes(:teacher_discipline_classroom)
         .map { |w| w.teacher_discipline_classroom.discipline_id }
         .uniq
  end

  # Turno do quadro de aulas para a disciplina/data (usado no form novo diário de frequência).
  def infer_daily_frequency_period_from_allocations(allocations, classroom_id:, discipline_id:)
    return nil if allocations.blank?

    periods_on_board = allocations.map do |allocation|
      allocation.lessons_board_lesson&.lessons_board&.period
    end.compact.map(&:to_i).uniq

    return nil if periods_on_board.empty?
    return periods_on_board.first if periods_on_board.size == 1

    teacher_p = current_teacher_period_by_classroom(classroom_id, discipline_id)
    teacher_p = teacher_p.to_i if teacher_p.present?
    return teacher_p if teacher_p.positive? && periods_on_board.include?(teacher_p)

    first = allocations.min_by do |allocation|
      lesson = allocation.lessons_board_lesson
      [
        lesson&.lesson_number.to_i,
        lesson&.lessons_board&.period.to_i
      ]
    end
    first&.lessons_board_lesson&.lessons_board&.period&.to_i
  end

  def fetch_disciplines_by_day
    date = parse_frequency_date(params.dig(:daily_frequency, :frequency_date))
    if date.blank? && @daily_frequency&.frequency_date.present?
      date = @daily_frequency.frequency_date.to_date
    end
    return [] if date.blank?

    classroom_id = resolved_classroom_id_for_lessons_board
    return [] if classroom_id.blank?

    schedule_discipline_ids_for_classroom_weekday(
      classroom_id: classroom_id,
      date: date,
      period: nil
    )
  end

  def fetch_disciplines_with_contents_by_day
    date_str = params.dig(:daily_frequency, :frequency_date)
    return [] unless date_str

    if date_str.include?('/')
      date = Date.strptime(date_str, "%d/%m/%Y")
    else
      date = Date.strptime(date_str, "%Y-%m-%d")
    end
    
    classroom_id = resolved_classroom_id_for_lessons_board
    return [] if classroom_id.blank?

    DisciplineContentRecord.by_classroom_id(classroom_id)
                           .by_date(date)
  end

  def fetch_knowledge_areas_with_contents_by_day
    date_str = params.dig(:daily_frequency, :frequency_date)
    return [] unless date_str

    if date_str.include?('/')
      date = Date.strptime(date_str, "%d/%m/%Y")
    else
      date = Date.strptime(date_str, "%Y-%m-%d")
    end
    
    classroom_id = resolved_classroom_id_for_lessons_board
    return [] if classroom_id.blank?

    KnowledgeAreaContentRecord.by_classroom_id(classroom_id)
                              .by_date(date)
                              .includes(:knowledge_areas)
  end

  def count_classes_of_the_day(discipline_id)
    return 0 unless @daily_schedule_discipline
    
    @daily_schedule_discipline.count { |d| d == discipline_id }
  end
  helper_method :count_classes_of_the_day

  def teacher_absence_blocks_frequency?(daily_frequency, class_numbers = nil)
    return false if current_teacher.blank? || daily_frequency.blank?

    TeacherAbsence.blocks_frequency?(
      classroom_id: daily_frequency.classroom_id,
      teacher_id: current_teacher.id,
      absence_date: daily_frequency.frequency_date,
      discipline_id: daily_frequency.discipline_id.presence,
      class_numbers: class_numbers.presence,
      unity_id: daily_frequency.classroom&.unity_id,
      period: daily_frequency.period
    )
  end

  def existing_frequencies_for_date?
    return false unless daily_frequency_params[:classroom_id].present? && daily_frequency_params[:frequency_date].present?

    frequency_date_str = daily_frequency_params[:frequency_date]
    
    # Parse da data
    if frequency_date_str.is_a?(String)
      if frequency_date_str.include?('/')
        frequency_date = Date.strptime(frequency_date_str, "%d/%m/%Y")
      else
        frequency_date = Date.strptime(frequency_date_str, "%Y-%m-%d")
      end
    else
      frequency_date = frequency_date_str.to_date
    end

    # Determina o período - usa o mesmo padrão do find_or_initialize_daily_frequency_by
    period = @period || daily_frequency_params[:period]
    period = period.to_i if period.is_a?(String)
    
    # Se há class_numbers, verifica frequências por disciplina
    if class_numbers?(@class_numbers)
      @class_numbers.each do |class_number|
        # Usa os mesmos critérios do find_or_initialize_daily_frequency_by
        search_params = {
          classroom_id: daily_frequency_params[:classroom_id],
          frequency_date: frequency_date,
          discipline_id: daily_frequency_params[:discipline_id],
          class_number: class_number,
          period: period
        }
        
        existing_frequency = DailyFrequency.find_by(search_params)
        
        # Se não encontrou e o período é FULL, tenta buscar em todos os períodos
        if existing_frequency.blank? && period == Periods::FULL.to_i
          existing_frequency = DailyFrequency.where(
            classroom_id: daily_frequency_params[:classroom_id],
            frequency_date: frequency_date,
            discipline_id: daily_frequency_params[:discipline_id],
            class_number: class_number,
            period: [Periods::FULL, Periods::MATUTINAL, Periods::VESPERTINE, Periods::NIGHTLY]
          ).first
        end

        return true if existing_frequency.present?
      end
      false
    else
      # Verifica frequência global - usa os mesmos critérios do find_or_initialize_daily_frequency_by
      search_params = {
        classroom_id: daily_frequency_params[:classroom_id],
        frequency_date: frequency_date,
        discipline_id: nil,
        class_number: nil,
        period: period
      }
      
      exists = DailyFrequency.exists?(search_params)
      
      # Se não encontrou e o período é FULL, tenta buscar em todos os períodos
      if !exists && period == Periods::FULL.to_i
        exists = DailyFrequency.exists?(
          classroom_id: daily_frequency_params[:classroom_id],
          frequency_date: frequency_date,
          discipline_id: nil,
          class_number: nil,
          period: [Periods::FULL, Periods::MATUTINAL, Periods::VESPERTINE, Periods::NIGHTLY]
        )
      end
      
      exists
    end
  end

  def get_discipline_content_record_id_by_date(discipline_id)
    @disciplines_with_contents ||= fetch_disciplines_with_contents_by_day
    result = @disciplines_with_contents.select { |c| c.discipline_id == discipline_id }.map(&:id)

    result.count >= 1 ? result.first : 0 
  end
  helper_method :get_discipline_content_record_id_by_date

  def get_knowledge_area_content_record_id_by_date(knowledge_area_id)
    @knowledge_areas_with_contents ||= fetch_knowledge_areas_with_contents_by_day
    Rails.logger.info("Knowledge areas with contents: #{@knowledge_areas_with_contents.inspect}")
    result = @knowledge_areas_with_contents.select { |c| c.knowledge_areas.map(&:id).include?(knowledge_area_id.to_i) }.map(&:id)

    result.count >= 1 ? result.first : 0 
  end
  helper_method :get_knowledge_area_content_record_id_by_date

  def parse_frequency_date(date_str)
    return if date_str.blank?

    if date_str.include?('/')
      Date.strptime(date_str, "%d/%m/%Y")
    else
      Date.strptime(date_str, "%Y-%m-%d")
    end
  rescue ArgumentError
    nil
  end

  def parsed_class_numbers_from_request
    raw = params[:class_numbers]
    return [] if raw.blank?

    raw.to_s.split(',').map(&:strip).reject(&:blank?).sort
  end

  # Falta geral: o JS ainda pode enviar números de aula sem disciplina; o modelo exige
  # (discipline + class_number) ou (nenhum dos dois). Alinhamos antes da validação.
  def apply_frequency_type_to_daily_frequency!
    if @daily_frequency.discipline_id.blank?
      @daily_frequency.discipline = nil
      @daily_frequency.discipline_id = nil
    end

    if current_frequency_type(@daily_frequency) == FrequencyTypes::GENERAL
      @daily_frequency.discipline_id = nil
      @daily_frequency.class_number = nil
      @class_numbers = []
      @discipline = nil
    elsif @class_numbers.present?
      @daily_frequency.class_number = @class_numbers.first
    else
      @daily_frequency.class_number = nil
    end
  end

end