class DailyFrequenciesInBatchsController < ApplicationController
  before_action :require_current_classroom
  before_action :require_teacher
  before_action :require_allocation_on_lessons_board
  before_action :set_number_of_classes, only: [:new, :form, :create, :create_or_update_multiple]
  before_action :authorize_daily_frequency, only: [:new, :create, :create_or_update_multiple]
  before_action :require_allow_to_modify_prev_years, only: [:create, :destroy_multiple]
  before_action :require_valid_daily_frequency_classroom
  before_action :require_valid_dates, only: [:create, :form]

  def new
    @admin_or_teacher = current_user.current_role_is_admin_or_employee?
    
    classroom_id = teacher_allocated.blank? ? nil : current_user_classroom.id
    discipline_id = teacher_allocated.blank? ? nil : current_user_discipline.id
    unity_id = current_unity&.id
    
    # Para o período, usar o período da turma ou tentar buscar o período do professor
    period = nil
    if @admin_or_teacher && current_user_classroom.present? && current_user_discipline.present?
      begin
        period = TeacherPeriodFetcher.new(
          current_teacher.id,
          current_user_classroom.id,
          current_user_discipline.id
        ).teacher_period
      rescue
        period = current_user_classroom.period
      end
    else
      period = current_user_classroom&.period
    end

    @frequency_in_batch_form = FrequencyInBatchForm.new(
      unity_id: unity_id,
      classroom_id: classroom_id,
      discipline_id: discipline_id,
      period: period
    )

    @frequency_type = current_frequency_type(current_user_classroom)

    set_options_by_user
  end

  # TODO método duplicado para ser acessado via GET, unificar
  def form
    start_date = params[:frequency_in_batch_form][:start_date].to_date
    end_date = params[:frequency_in_batch_form][:end_date].to_date

    @dates = [*start_date..end_date]
    @classroom = Classroom.includes(:unity).find(params[:frequency_in_batch_form][:classroom_id])
    @discipline = Discipline.find(params[:frequency_in_batch_form][:discipline_id]) if params[:frequency_in_batch_form][:discipline_id].present?

    return unless view_data

    render :create_or_update_multiple
  end

  def create
    start_date = params[:frequency_in_batch_form][:start_date].to_date
    end_date = params[:frequency_in_batch_form][:end_date].to_date

    @dates = [*start_date..end_date]
    @classroom = Classroom.includes(:unity).find(params[:frequency_in_batch_form][:classroom_id])
    @discipline = Discipline.find(params[:frequency_in_batch_form][:discipline_id]) if params[:frequency_in_batch_form][:discipline_id].present?

    return unless view_data

    render :create_or_update_multiple
  end

  def create_or_update_multiple
    daily_frequency_attributes = daily_frequency_in_batchs_params
    daily_frequencies_attributes = daily_frequencies_in_batch_params
    receive_email_confirmation = ActiveRecord::Type::Boolean.new.cast(
      daily_frequency_attributes[:frequency_in_batch_form][:receive_email_confirmation]
    )
    dates = []

    ActiveRecord::Base.transaction do
      daily_frequencies_attributes[:daily_frequencies].each_value do |daily_frequency_students_params|
        daily_frequency_data = daily_frequency_attributes
        daily_frequency_data[:frequency_date] = daily_frequency_students_params[:date]
        daily_frequency_data[:class_number] = daily_frequency_students_params[:class_number]

        if daily_frequency_attributes[:frequency_type] == FrequencyTypes::GENERAL
          daily_frequency_data[:class_number] = nil
          daily_frequency_data[:discipline_id] = nil
        end

        daily_frequency = find_or_initialize_daily_frequency_by(daily_frequency_data[:frequency_date],
                                                                daily_frequency_data[:class_number],
                                                                daily_frequency_data[:unity_id],
                                                                daily_frequency_data[:classroom_id],
                                                                daily_frequency_data[:discipline_id],
                                                                daily_frequency_data[:period])

        daily_frequency_students_params[:students_attributes].each_value do |student_attributes|
          away = 0
          daily_frequency_student = daily_frequency.build_or_find_by_student(student_attributes[:student_id])

          if student_attributes[:absence_justification_student_id].to_i.eql?(-1)
            params = {
              student_ids: [student_attributes[:student_id]],
              absence_date: daily_frequency_data[:frequency_date],
              justification: nil,
              absence_date_end: daily_frequency_data[:frequency_date],
              unity_id: daily_frequency_data[:unity_id],
              classroom_id: daily_frequency_data[:classroom_id],
              class_number: daily_frequency_data[:class_number],
            }

            absence_justification = AbsenceJustification.new(params)
            absence_justification.teacher = current_teacher
            absence_justification.user = current_user
            absence_justification.school_calendar = current_school_calendar
            absence_justification.period = daily_frequency_data[:period]

            absence_justification.save

            student_attributes[:absence_justification_student_id] = absence_justification.absence_justifications_students.first.id
          end

          daily_frequency_student.present = student_attributes[:present].blank? ? away : student_attributes[:present]
          daily_frequency_student.type_of_teaching = student_attributes[:type_of_teaching]
          daily_frequency_student.active = student_attributes[:active]
          daily_frequency_student.absence_justification_student_id = student_attributes[:absence_justification_student_id]

          daily_frequency_student.save!
        end

        if daily_frequency.save!
          UniqueDailyFrequencyStudentsCreator.call_worker(
            current_entity.id,
            daily_frequency.classroom_id,
            daily_frequency.frequency_date,
            current_teacher_id
          )

          dates << daily_frequency.frequency_date.to_date.strftime('%d/%m/%Y')
        end
      end
    end

    if receive_email_confirmation
      ReceiptMailer.delay.notify_daily_frequency_in_batch_success(
        current_user.first_name,
        current_user.email,
        "#{request.base_url}#{create_or_update_multiple_daily_frequencies_in_batchs_path}",
        dates,
        Classroom.find(daily_frequency_attributes[:classroom_id].to_i).description,
        Unity.find(daily_frequency_attributes[:unity_id].to_i).name
      )
    end

    flash[:success] = t('.daily_frequency_success')

    @dates = [*params[:start_date].to_date..params[:end_date].to_date]
    @classroom = Classroom.includes(:unity).find(daily_frequency_attributes[:classroom_id])

    if daily_frequency_attributes[:discipline_id].present?
      @discipline = Discipline.find(daily_frequency_attributes[:discipline_id])
    end

    view_data

    render :create_or_update_multiple
  end

  def destroy_multiple
    @daily_frequencies = DailyFrequency.where(id: params[:daily_frequencies_ids])

    if @daily_frequencies.any?
      @daily_frequencies.each(&:destroy)

      flash[:success] = t('daily_frequencies_in_batchs.destroy_multiple.success')

      redirect_to new_daily_frequencies_in_batch_path
    else
      flash[:alert] = t('daily_frequencies_in_batchs.destroy_multiple.alert')

      redirect_to new_daily_frequencies_in_batch_path
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

  def fetch_frequency_type
    return if params[:classroom_id].blank?

    classroom = Classroom.find(params[:classroom_id])

    render json: current_frequency_type(classroom)
  end

  def fetch_teacher_allocated
    return if params[:classroom_id].blank? || params[:discipline_id].blank?

    @classroom = Classroom.find(params[:classroom_id])
    @discipline = params[:discipline_id]

    render json: teacher_allocated
  end

  private

  def authorize_daily_frequency
    @daily_frequency = DailyFrequency.new.localized

    authorize @daily_frequency
  end

  def view_data
    @period = current_teacher_period != Periods::FULL.to_i ? current_teacher_period : @classroom.period
    @general_configuration = GeneralConfiguration.current
    @frequency_type = current_frequency_type(@classroom)
    params['dates'] = allocation_dates(@dates)
    @frequency_form = FrequencyInBatchForm.new
    @absence_justification = AbsenceJustification.new
    @absence_justification.school_calendar = current_school_calendar
    @students = []
    @students_list = []

    student_enrollments_ids = []
    student_ids = []
    dates = []
    params['dates'].each { |date| dates << date['date'] }

    if dates.empty?
      flash.now[:warning] = t('daily_frequencies_in_batchs.create_or_update_multiple.no_school_day')

      # Inicializar o formulário com os parâmetros corretos para renderizar :new
      start_date = params[:frequency_in_batch_form][:start_date] rescue nil
      end_date = params[:frequency_in_batch_form][:end_date] rescue nil
      
      @frequency_in_batch_form = FrequencyInBatchForm.new(
        unity_id: @classroom.unity_id,
        classroom_id: @classroom.id,
        discipline_id: @discipline&.id,
        period: @period,
        start_date: start_date,
        end_date: end_date
      )
      @admin_or_teacher = current_user.current_role_is_admin_or_employee?
      set_options_by_user

      render :new

      return false
    end

    # Agrupar student_enrollments por student_id para evitar duplicatas
    student_enrollments_by_student = fetch_student_enrollments.group_by { |se| se.student_id }
    
    student_enrollments_by_student.each do |student_id, student_enrollments|
      student_enrollment = student_enrollments.first
      student_enrollments_ids << student_enrollment.id
      student = student_enrollment.student
      student_ids << student.id
      
      # Buscar todos os enrollment_classrooms do aluno na turma
      enrollment_classrooms = StudentEnrollmentClassroom.joins(:student_enrollment)
                                                         .where(student_enrollments: { student_id: student_id })
                                                         .by_classroom(@classroom.id)
                                                         .order('changed_at DESC, joined_at DESC')
      
      # Selecionar o enrollment_classroom mais recente baseado em changed_at e joined_at
      most_recent_enrollment_classroom = enrollment_classrooms.max_by do |ec|
        changed_at = ec.changed_at
        joined_at = ec.joined_at
        
        changed_at_date = changed_at.present? ? (changed_at.is_a?(Date) ? changed_at : (changed_at.to_date rescue nil)) : nil
        joined_at_date = joined_at.present? ? (joined_at.is_a?(Date) ? joined_at : (joined_at.to_date rescue nil)) : nil
        
        if changed_at_date && joined_at_date
          [changed_at_date, joined_at_date].max
        elsif changed_at_date
          changed_at_date
        elsif joined_at_date
          joined_at_date
        else
          Date.new(1900, 1, 1)
        end
      end
      
      type_of_teaching = most_recent_enrollment_classroom&.type_of_teaching

      next if student.blank?

      @students_list << student
      @students << {
        student: student,
        type_of_teaching: type_of_teaching
      }
    end

    if @students.blank?
      flash.now[:warning] = t('daily_frequencies_in_batchs.create_or_update_multiple.warning_no_students')

      # Inicializar o formulário com os parâmetros corretos para renderizar :new
      start_date = params[:frequency_in_batch_form][:start_date] rescue nil
      end_date = params[:frequency_in_batch_form][:end_date] rescue nil
      
      @frequency_in_batch_form = FrequencyInBatchForm.new(
        unity_id: @classroom.unity_id,
        classroom_id: @classroom.id,
        discipline_id: @discipline&.id,
        period: @period,
        start_date: start_date,
        end_date: end_date
      )
      @admin_or_teacher = current_user.current_role_is_admin_or_employee?
      set_options_by_user

      render :new

      return false
    end

    dependences = student_has_dependence(student_enrollments_ids, dates)
    inactives_on_date = students_inactive_on_range(student_enrollments_ids, dates)
    exempteds_from_discipline = student_exempted_from_discipline_in_range(student_enrollments_ids, dates)
    active_searchs = ActiveSearch.new.in_active_search_in_range(student_enrollments_ids, dates)

    @absence_justifications = AbsenceJustifiedOnDate.call(
      students: student_ids,
      date: dates.first,
      end_date: dates.last,
      classroom: current_user_classroom.id,
      period: @period
    )

    @additional_data = additional_data(dates, student_ids, dependences,
                                       inactives_on_date, exempteds_from_discipline, active_searchs)
    
    # Buscar todas as frequências salvas do período para verificar se há alguma para exibir o botão excluir
    # Isso inclui frequências que não estão no quadro de horários (como aulas registradas anteriormente)
    start_date = dates.first.to_date
    end_date = dates.last.to_date
    
    # Buscar frequências de forma mais ampla para garantir que encontre todos os registros
    # Busca apenas por classroom, data e disciplina (se houver), sem filtro de period/teacher
    # Isso garante que encontre todos os registros que existem no banco
    @saved_frequencies = DailyFrequency.by_classroom_id(@classroom.id)
                                       .by_frequency_date_between(start_date, end_date)
    
    if @frequency_type == FrequencyTypes::GENERAL
      @saved_frequencies = @saved_frequencies.general_frequency
    else
      @saved_frequencies = @saved_frequencies.by_discipline_id(@discipline.id) if @discipline.present?
    end
    
    # Coletar os IDs primeiro para garantir que temos os dados
    # Não aplicar filtro de period/teacher aqui, pois queremos encontrar TODOS os registros existentes
    @saved_frequencies_ids = @saved_frequencies.pluck(:id)
    @has_saved_frequencies = @saved_frequencies_ids.present?
    
    true
  end

  def additional_data(dates, student_ids, dependences, inactives_on_date, exempteds_from_discipline, active_searchs)
    additional_data = []
    dates.each do |date|
      student_ids.each do |student_id|
        if active_searchs.any?
          active_searchs.each do |active_search|
            next if active_search[:date] != date || !active_search[:student_ids].include?(student_id)

            additional_class = 'in-active-search'
            tooltip = t('daily_frequencies_in_batchs.create_or_update_multiple.in_active_search_tooltip')
            additional_data << { date: active_search[:date], student_id: student_id,
                                 additional_class: additional_class, tooltip:  tooltip }
          end
        end
        if dependences.any?
          dependences.each do |dependence|
            next if dependence[:date] != date || !dependence[:student_ids].include?(student_id)

            tooltip = t('daily_frequencies_in_batchs.create_or_update_multiple.dependence_students_tooltip')
            additional_data << { date: dependence[:date], student_id: student_id,
                                 additional_class: '', tooltip:  tooltip }
          end
        end
        if exempteds_from_discipline.any?
          exempteds_from_discipline.each do |exempted_from_discipline|
            next if exempted_from_discipline[:date] != date || !exempted_from_discipline[:student_ids].include?(student_id)

            additional_class = 'exempted'
            tooltip = t('daily_frequencies_in_batchs.create_or_update_multiple.exempted_students_from_discipline_tooltip')
            additional_data << { date: exempted_from_discipline[:date], student_id: student_id,
                                 additional_class: additional_class, tooltip:  tooltip }
          end
        end
        if inactives_on_date.any?
          inactives_on_date.each do |inactive_on_date|
            next if inactive_on_date[:date] != date || !inactive_on_date[:student_ids].include?(student_id)

            additional_class = 'inactive'
            tooltip = t('daily_frequencies_in_batchs.create_or_update_multiple.inactive_students_tooltip')
            additional_data << { date: inactive_on_date[:date], student_id: student_id,
                                 additional_class: additional_class, tooltip:  tooltip }
          end
        end
      end
    end
    additional_data
  end

  def allocation_dates(dates)
    allocation_dates = []
    dates.each do |date|
      lesson_numbers = []
      if @frequency_type == FrequencyTypes::GENERAL
        allocations =  LessonsBoardLessonWeekday.includes(:lessons_board_lesson)
                                                .by_classroom(@classroom.id)
                                                .by_teacher(current_teacher_id)
                                                .by_weekday(date.strftime("%A").downcase)
                                                .order('lessons_board_lessons.lesson_number')
      else
        allocations =  LessonsBoardLessonWeekday.includes(:lessons_board_lesson)
                                                .by_classroom(@classroom.id)
                                                .by_teacher(current_teacher_id)
                                                .by_discipline(@discipline.id)
                                                .by_weekday(date.strftime("%A").downcase)
                                                .order('lessons_board_lessons.lesson_number')
      end

      allocations.by_period(@period) if @period.present?

      if current_user.current_role_is_admin_or_employee?
        school_calendar = current_school_calendar
      else
        school_calendar = CurrentSchoolCalendarFetcher.new(current_unity, @classroom, current_school_year).fetch
      end

      valid_day = SchoolDayChecker.new(school_calendar, date, nil, nil, nil).day_allows_entry?

      next if allocations.empty? || !valid_day

      if @frequency_type == FrequencyTypes::BY_DISCIPLINE
        allocations.each { |allocattion| lesson_numbers << allocattion.lessons_board_lesson.lesson_number.to_i }
        allocation_dates << build_hash(date, lesson_numbers.sort.uniq)
      else
        allocation_dates << build_hash(date, nil)
      end
    end

    allocation_dates.first(15)
  end

  def find_or_initialize_daily_frequency_by(date, lesson_number, unity_id, classroom_id, discipline_id, period)
    # Buscar primeiro sem o period para encontrar frequências registradas por outros professores
    search_params = {
      classroom_id: classroom_id,
      frequency_date: date,
      discipline_id: discipline_id,
      class_number: lesson_number
    }
    
    # Tenta encontrar sem o period primeiro (para encontrar frequências de outros professores)
    daily_frequency = DailyFrequency.find_by(search_params)
    
    # Se não encontrou, tenta com o period também
    if daily_frequency.nil?
      search_params_with_period = search_params.dup
      search_params_with_period[:period] = period
      daily_frequency = DailyFrequency.find_by(search_params_with_period)
    end
    
    # Se ainda não encontrou, inicializa um novo registro
    if daily_frequency.nil?
      search_params[:period] = period
      daily_frequency = DailyFrequency.new(search_params)
    end
    
    daily_frequency.tap do |daily_frequency_record|
      daily_frequency_record.unity_id = unity_id
      daily_frequency_record.school_calendar_id = current_school_calendar.id
      daily_frequency_record.owner_teacher_id = daily_frequency_record.teacher_id = current_teacher_id
      daily_frequency_record.origin = OriginTypes::WEB
    end

    # Recarrega do banco se já estiver persistido para garantir que tem todos os dados atualizados
    daily_frequency.reload if daily_frequency.persisted?

    daily_frequency
  end

  def build_hash(date, lesson_numbers)
    return if date.blank?

    daily_frequencies = []
    if lesson_numbers.nil?
      daily_frequencies << find_or_initialize_daily_frequency_by(date, nil, @classroom.unity.id, @classroom.id, nil, @period)
    else
      lesson_numbers.each do |lesson_number|
        daily_frequencies << find_or_initialize_daily_frequency_by(date, lesson_number,
                                                                   @classroom.unity.id, @classroom.id,
                                                                   @discipline.id, @period)
      end
    end

    {
      'date': date,
      'lesson_numbers': lesson_numbers,
      'daily_frequencies': daily_frequencies
    }
  end

  def daily_frequency_in_batchs_params
    params.permit(
      :unity_id,
      :classroom_id,
      :discipline_id,
      :frequency_type,
      :period,
      frequency_in_batch_form: [
        :receive_email_confirmation
      ]
    )
  end

  def daily_frequencies_in_batch_params
    params.require(:daily_frequency).permit(
      daily_frequencies: [
        :date,
        :class_number,
        students_attributes: [
          :id, :daily_frequency_id, :student_id, :present, :active, :dependence, :type_of_teaching, :absence_justification_student_id
        ]
      ]
    )
  end

  def current_frequency_type(classroom)
    absence_type_definer = FrequencyTypeDefiner.new(
      classroom,
      current_teacher,
      year: classroom.year
    )
    absence_type_definer.define!

    absence_type_definer.frequency_type
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

  def current_teacher_period
    TeacherPeriodFetcher.new(
      current_teacher.id,
      @classroom.id,
      @discipline.id
    ).teacher_period
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

  def fetch_student_enrollments
    StudentEnrollmentsList.new(
      classroom: @classroom,
      discipline: @discipline,
      start_at: params[:start_date] || params[:frequency_in_batch_form][:start_date],
      end_at: params[:end_date] || params[:frequency_in_batch_form][:end_date],
      search_type: :by_date_range,
      period: @period
    ).student_enrollments
  end

  def students_inactive_on_range(student_enrollments_ids, dates)
    inactives = []
    
    # Agrupar student_enrollments por student_id para considerar apenas a matrícula mais recente
    student_enrollments_by_student = StudentEnrollment.where(id: student_enrollments_ids)
                                                       .includes(:student)
                                                       .group_by { |se| se.student_id }

    dates.each do |date|
      inactives_students_ids = []
      
      student_enrollments_by_student.each do |student_id, student_enrollments|
        # Para cada aluno, buscar todos os enrollment_classrooms na turma
        enrollment_classrooms = StudentEnrollmentClassroom.joins(:student_enrollment)
                                                           .where(student_enrollments: { student_id: student_id })
                                                           .by_classroom(@classroom.id)
        
        # Primeiro, verificar se há algum enrollment_classroom ativo na data específica
        # Usar o mesmo critério do scope by_date: date >= joined_at AND (date < left_at OR left_at é vazio)
        active_enrollment_classrooms = enrollment_classrooms.select do |ec|
          joined_at_str = ec.joined_at
          left_at_str = ec.left_at
          
          # Converter para Date
          joined_at = joined_at_str.present? ? (joined_at_str.is_a?(Date) ? joined_at_str : (joined_at_str.to_date rescue nil)) : nil
          left_at = left_at_str.present? ? (left_at_str.is_a?(Date) ? left_at_str : (left_at_str.to_date rescue nil)) : nil
          
          # Verificar se está ativo na data usando o mesmo critério do scope by_date
          if joined_at && date >= joined_at
            # Se left_at é vazio/nil, está ativo
            # Se left_at existe, verificar se date < left_at (não <=, igual ao scope)
            left_at.nil? || left_at_str.blank? || date < left_at
          else
            false
          end
        end
        
        if active_enrollment_classrooms.any?
          # Se há ativos na data, usar o mais recente baseado em changed_at e joined_at
          most_recent_enrollment_classroom = active_enrollment_classrooms.max_by do |ec|
            changed_at = ec.changed_at
            joined_at = ec.joined_at
            
            changed_at_date = changed_at.present? ? (changed_at.is_a?(Date) ? changed_at : (changed_at.to_date rescue nil)) : nil
            joined_at_date = joined_at.present? ? (joined_at.is_a?(Date) ? joined_at : (joined_at.to_date rescue nil)) : nil
            
            if changed_at_date && joined_at_date
              [changed_at_date, joined_at_date].max
            elsif changed_at_date
              changed_at_date
            elsif joined_at_date
              joined_at_date
            else
              Date.new(1900, 1, 1)
            end
          end
          
          # Se encontrou um ativo, o aluno está ativo na data
          # Não adicionar à lista de inativos
        else
          # Se não há ativo na data, verificar se há algum que estava ativo antes da transferência
          # e foi transferido depois da data (caso: frequência de antes da transferência)
          enrollment_classroom_before_transfer = enrollment_classrooms.find do |ec|
            joined_at = ec.joined_at.to_date rescue nil
            left_at = ec.left_at.to_date rescue nil if ec.left_at.present?
            
            # Verificar se estava ativo na data (joined_at <= date)
            # e foi transferido depois (left_at > date ou left_at é nil)
            if joined_at && joined_at <= date
              left_at.nil? || left_at.blank? || left_at > date
            else
              false
            end
          end
          
          if enrollment_classroom_before_transfer
            # Aluno estava ativo na data mas foi transferido depois
            # Não adicionar à lista de inativos
          else
            # Aluno foi transferido antes da data ou não está na turma
            # Adicionar à lista de inativos
            inactives_students_ids << student_id
          end
        end
      end
      
      inactives << { date: date, student_ids: inactives_students_ids } if inactives_students_ids.any?
    end

    inactives
  end

  def set_number_of_classes
    @number_of_classes = current_school_calendar.number_of_classes
  end

  def require_teacher
    return if current_teacher.present?

    flash[:alert] = t('errors.daily_frequencies.require_teacher')
    redirect_to root_path
  end

  def student_has_dependence(student_enrollments, frequency_dates)
    students_dependences = StudentEnrollmentDependence.by_student_enrollment(student_enrollments)
                                                      .by_discipline(@discipline.id)
                                                      .includes(student_enrollment: [:student])
                                                      .pluck('students.id')

    return students_dependences if students_dependences&.empty?

    students_with_dependences = []

    frequency_dates.each do |date|
      students_with_dependences << { date: date, student_ids: students_dependences }
    end

    students_with_dependences
  end

  def student_exempted_from_discipline_in_range(student_enrollments_ids, frequency_dates)
    return if @discipline.blank?

    exempteds = []
    steps = []

    frequency_dates.each do |date|
      steps << current_school_calendar.step(date.to_date).try(:to_number)
    end

    steps.uniq.compact.each do |step_number|
      students_exempteds = StudentEnrollmentExemptedDiscipline.where(student_enrollment_id: student_enrollments_ids)
                                                              .by_discipline(@discipline.id)
                                                              .by_step_number(step_number)
                                                              .includes(student_enrollment: [:student])
                                                              .pluck('students.id')
      next if students_exempteds&.empty?

      exempteds << { step_number: step_number, student_ids: students_exempteds }
    end

    exempteds.compact
  end

  def require_valid_daily_frequency_classroom
    return unless params[:frequency_in_batch_form]
    return unless params[:frequency_in_batch_form][:classroom_id]
    return if current_user.current_classroom_id == params[:frequency_in_batch_form][:classroom_id].to_i

    redirect_to new_daily_frequency_path
  end

  def require_allocation_on_lessons_board
    return if teacher_allocated

    @admin_or_teacher = current_user.current_role_is_admin_or_employee?

    flash[:alert] = t('errors.daily_frequencies.require_lessons_board')
    redirect_to root_path if @admin_or_teacher
  end

  def set_options_by_user
    return fetch_linked_by_teacher unless @admin_or_teacher

    @classrooms ||= [current_user_classroom]
    @disciplines ||= [current_user_discipline]
  end

  def teacher_allocated
    @classroom ||= current_user_classroom
    @discipline ||= current_user_discipline

    frequency_type = current_frequency_type(@classroom)

    if frequency_type == FrequencyTypes::BY_DISCIPLINE
      LessonsBoard.by_teacher(current_teacher)
                  .by_classroom(@classroom)
                  .by_discipline(@discipline)
                  .exists?
    else
      LessonsBoard.by_teacher(current_teacher)
                  .by_classroom(@classroom)
                  .exists?
    end
  end

  def invalid_dates?(start_date, end_date, classroom = nil, discipline = nil)
    if start_date.nil? || end_date.nil?
      flash[:error] = t('daily_frequencies_in_batchs.create_or_update_multiple.blank_dates')
      return true
    end

    if start_date > end_date
      flash[:error] = t('daily_frequencies_in_batchs.create_or_update_multiple.start_date_greater_end_date')
      return true
    end

    # Verificar se há pelo menos uma data letiva no intervalo
    # Permite que a data inicial ou final não sejam letivas, desde que haja datas letivas no intervalo
    classroom_id = classroom&.id || @classroom&.id
    discipline_id = discipline&.id || @discipline&.id
    school_day_checker = SchoolDayChecker.new(current_school_calendar, start_date, nil, classroom_id, discipline_id)
    school_dates = school_day_checker.school_dates_between(start_date, end_date)
    
    if school_dates.empty?
      flash[:error] = t('daily_frequencies_in_batchs.create_or_update_multiple.no_school_day')
      return true
    end

    # if start_date > Time.zone.today || end_date > Time.zone.today
    #   flash[:error] = t('daily_frequencies_in_batchs.create_or_update_multiple.future_date')
    #   return true
    # end

    false
  end

  def require_valid_dates
    start_date = params[:frequency_in_batch_form][:start_date].to_date
    end_date = params[:frequency_in_batch_form][:end_date].to_date
    
    # Buscar classroom e discipline para validação
    classroom_id = params[:frequency_in_batch_form][:classroom_id]
    discipline_id = params[:frequency_in_batch_form][:discipline_id]
    classroom = Classroom.find(classroom_id) if classroom_id.present?
    discipline = Discipline.find(discipline_id) if discipline_id.present?

    if invalid_dates?(start_date, end_date, classroom, discipline)
      redirect_to(new_daily_frequencies_in_batch_path) and return
    end
  end

  def fetch_linked_by_teacher
    @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(current_teacher.id, current_unity, current_school_year)
    @disciplines = []
    @classrooms = []

    # Remove turmas que não estão no quadro de aulas
    @fetch_linked_by_teacher[:classrooms].each do |classroom|
      lesson_board = LessonsBoard.by_teacher(current_teacher)
                                 .by_classroom(classroom)
                                 .exists?
      @classrooms << classroom if lesson_board
    end

    # Remove disciplinas que não estão no quadro de aulas
    @fetch_linked_by_teacher[:disciplines].each do |discipline|
      lesson_board = LessonsBoard.by_teacher(current_teacher)
                                 .by_classroom(@classrooms)
                                 .by_discipline(discipline)
                                 .exists?
      @disciplines << discipline if lesson_board
    end
    @disciplines.uniq
  end
end
