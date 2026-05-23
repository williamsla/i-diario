class DisciplineContentRecordsController < ApplicationController
  has_scope :page, default: 1
  has_scope :per, default: 10

  before_action :require_current_classroom, only: [:index, :new, :edit, :create, :update]
  before_action :require_current_teacher
  before_action :require_current_classroom, only: [:index, :new, :create, :edit, :update]
  before_action :require_allow_to_modify_prev_years, only: [:create, :update, :destroy, :clone]
  before_action :set_number_of_classes, only: [:new, :create, :edit, :update, :show]
  before_action :allow_class_number, only: [:index, :new, :edit, :show]

  def check_teacher_absence
    record_date = parse_record_date(params[:record_date])
    classroom_id = params[:classroom_id].presence || current_user_classroom&.id
    discipline_id = params[:discipline_id].presence
    class_number = params[:class_number].presence

    blocked = if record_date.blank? || classroom_id.blank?
                false
              else
                classroom = Classroom.find_by(id: classroom_id)
                cr = ContentRecord.new(record_date: record_date, classroom_id: classroom_id)
                cr.classroom = classroom
                dcr = DisciplineContentRecord.new(discipline_id: discipline_id, class_number: class_number)
                dcr.content_record = cr
                teacher_absence_blocks_content_record?(dcr, class_number.present? ? [class_number] : nil)
              end

    render json: { blocked: blocked }
  end

  def index
    params[:filter] ||= {}
    author_type = PlansAuthors::ALL.to_s if params[:filter].empty?
    author_type ||= (params[:filter] || []).delete(:by_author)
    
    @classrooms ||= [current_user_classroom]
    @disciplines ||= [current_user_discipline]
    
    fetch_discipline_content_records_by_user

    if author_type.present?
      @discipline_content_records = @discipline_content_records.by_author(author_type, current_teacher.id)
    end

    authorize @discipline_content_records
  end

  def show
    @discipline_content_record = DisciplineContentRecord.find(params[:id]).localized

    authorize @discipline_content_record
  end

  def new
    set_options_by_user

    @discipline_content_record = DisciplineContentRecord.new.localized

    # verifica se o usuário passou o parametro da disciplina na URL. Normalmente usado em modal
    if params[:discipline_id].present?
      @discipline_content_record.discipline_id = params[:discipline_id]
    else
      @discipline_content_record.discipline_id = current_user.current_discipline_id
    end

    @discipline_content_record.content_record ||= ContentRecord.new

    if params[:recorded_at].present?
      record_date = Date.parse(params[:recorded_at])
    else
      record_date = Time.zone.now
    end

    @discipline_content_record.build_content_record(
      record_date: record_date,
      unity_id: current_unity.id,
      classroom_id: current_user_classroom.id
    )

    @has_lesson_board_map = false

    if params[:class_number].present?
      @class_number_qtd = params[:class_number]
    else
      qtd = LessonBoardsFetcher.new(current_user).count_lessons(
        current_user_classroom.id,
        @discipline_content_record.discipline_id,
        @discipline_content_record.content_record.record_date
      )
      @has_lesson_board_map = qtd > 0

      @class_number_qtd = qtd || 0
    end
 
    @class_numbers = []

    @teacher_absence_blocks_date = teacher_absence_blocks_content_record?(@discipline_content_record)
     
    authorize @discipline_content_record
  end

  def create
    @discipline_content_record = DisciplineContentRecord.new(resource_params)
    @discipline_content_record.content_record.teacher = current_teacher
    # Remove qualquer conteúdo que possa ter sido processado automaticamente pelo accepts_nested_attributes_for
    # Para objetos não persistidos, precisamos remover da memória
    @discipline_content_record.content_record.content_records_contents.each(&:mark_for_destruction) if @discipline_content_record.content_record.content_records_contents.loaded?
    @discipline_content_record.content_record.objectives_content_records.each(&:mark_for_destruction) if @discipline_content_record.content_record.objectives_content_records.loaded?
    # Define os IDs manualmente (isso substitui qualquer conteúdo existente)
    @discipline_content_record.content_record.content_ids = content_ids
    @discipline_content_record.content_record.objective_ids = objective_ids
    @discipline_content_record.content_record.origin = OriginTypes::WEB
    @discipline_content_record.content_record.creator_type = 'discipline_content_record'
    @discipline_content_record.content_record.teacher = current_teacher
    @discipline_content_record.teacher_id = current_teacher_id
    
    authorize @discipline_content_record

    if teacher_absence_blocks_content_record?(@discipline_content_record)
      set_options_by_user
      flash.now[:alert] = I18n.t('discipline_content_records.create.blocked_by_teacher_absence')
      return render :new
    end

    @class_numbers = resource_params[:class_number]
    
    if @class_numbers.present? && @class_numbers.size > 0
      return render_content_with_multiple_class_numbers
    end

    # Usa transação para garantir atomicidade e evitar condições de corrida
    saved = false
    begin
      ActiveRecord::Base.transaction do
        # Valida antes de salvar para capturar erros
        unless @discipline_content_record.valid?
          Rails.logger.error "=== Erros de validação antes do save: #{@discipline_content_record.errors.full_messages.inspect} ==="
          Rails.logger.error "=== Content Record errors: #{@discipline_content_record.content_record.errors.full_messages.inspect} ==="
          raise ActiveRecord::RecordInvalid.new(@discipline_content_record) unless @discipline_content_record.errors.empty?
        end

        saved = @discipline_content_record.save
        
        # Verifica se realmente foi salvo
        unless saved && @discipline_content_record.persisted?
          Rails.logger.error "=== Save falhou ou registro não foi persistido ==="
          Rails.logger.error "=== Erros: #{@discipline_content_record.errors.full_messages.inspect} ==="
          Rails.logger.error "=== Content Record errors: #{@discipline_content_record.content_record.errors.full_messages.inspect} ==="
          raise ActiveRecord::RecordInvalid.new(@discipline_content_record)
        end

        # Valida class_numbers dentro da transação
        unless validate_class_numbers
          Rails.logger.error "=== validate_class_numbers falhou ==="
          raise ActiveRecord::RecordInvalid.new(@discipline_content_record)
        end

      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "=== Exceção ao salvar: #{e.message} ==="
      saved = false
    rescue => e
      Rails.logger.error "=== Erro inesperado ao salvar: #{e.class} - #{e.message} ==="
      Rails.logger.error e.backtrace.join("\n")
      saved = false
    end

    if saved
      if params[:modal] == 'true'
        render html: "<script>window.parent.postMessage({ action: 'closeContentModalAndReload' }, '*');</script>".html_safe, layout: false
      else
        set_current_discipline_id(resource_params[:discipline_id])
        
        respond_with @discipline_content_record, location: discipline_content_records_path
      end
    else
      error_messages = @discipline_content_record.errors.full_messages
      content_record_errors = @discipline_content_record.content_record.errors.full_messages
      
      Rails.logger.error "=== Falha ao salvar registro ==="
      Rails.logger.error "=== DisciplineContentRecord errors: #{error_messages.inspect} ==="
      Rails.logger.error "=== ContentRecord errors: #{content_record_errors.inspect} ==="
      
      # Adiciona mensagem de erro ao flash se houver erros
      all_errors = (error_messages + content_record_errors).compact
      if all_errors.any?
        flash.now[:alert] = all_errors.join(', ')
      else
        flash.now[:alert] = 'Não foi possível salvar o registro. Por favor, tente novamente.'
      end
      
      set_options_by_user

      render :new
    end
  end

  def edit
    set_options_by_user

    @discipline_content_record = DisciplineContentRecord.find(params[:id]).localized

    qtd = LessonBoardsFetcher.new(current_user).count_lessons(
        current_user_classroom.id,
        @discipline_content_record.discipline_id,
        @discipline_content_record.content_record.record_date
    )
    @has_lesson_board_map = qtd > 0

    if @discipline_content_record[:class_number].present?
      @class_number_qtd = @discipline_content_record[:class_number]
    else      
      @class_number_qtd = qtd || 0
    end

    @teacher_absence_blocks_date = teacher_absence_blocks_content_record?(@discipline_content_record)
 
    authorize @discipline_content_record
  end

  def update
    @discipline_content_record = DisciplineContentRecord.find(params[:id])
    @discipline_content_record.assign_attributes(resource_params)
    
    # Limpa qualquer conteúdo que possa ter sido processado automaticamente pelo accepts_nested_attributes_for
    @discipline_content_record.content_record.content_records_contents.clear
    @discipline_content_record.content_record.objectives_content_records.clear
    # Garantir que apenas os conteúdos e objetivos enviados sejam salvos
    @discipline_content_record.content_record.content_ids = content_ids
    @discipline_content_record.content_record.objective_ids = objective_ids
    @discipline_content_record.content_record.teacher = current_teacher
    @discipline_content_record.content_record.origin = OriginTypes::WEB
    @discipline_content_record.teacher_id = current_teacher_id
    @discipline_content_record.current_user = current_user
    @discipline_content_record.content_record.creator_type = 'discipline_content_record'
    
    authorize @discipline_content_record

    if teacher_absence_blocks_content_record?(@discipline_content_record)
      set_options_by_user
      flash.now[:alert] = I18n.t('discipline_content_records.update.blocked_by_teacher_absence')
      return render :edit
    end

    if @discipline_content_record.save
      if params[:modal] == 'true'
        render html: "<script>window.parent.postMessage({ action: 'closeContentModalAndReload' }, '*');</script>".html_safe, layout: false
      else
        respond_with @discipline_content_record, location: discipline_content_records_path
      end
    else
      Rails.logger.error @discipline_content_record.errors.full_messages

      set_options_by_user

      render :edit
    end
  end

  def destroy
    @discipline_content_record = DisciplineContentRecord.find(params[:id]).localized

    authorize @discipline_content_record

    @discipline_content_record.destroy

    respond_with @discipline_content_record, location: discipline_content_records_path
  end

  def history
    @discipline_content_record = DisciplineContentRecord.find(params[:id])

    authorize @discipline_content_record

    respond_with @discipline_content_record
  end

  def clone
    @form = DisciplineContentRecordClonerForm.new(clone_params.merge(teacher: current_teacher))

    if @form.clone!
      flash[:success] = "Registro de conteúdo por disciplina copiado com sucesso!"
    end
  end

  private

  def render_content_with_multiple_class_numbers
    @class_numbers = resource_params[:class_number].split(',').map(&:strip).sort
    @discipline_content_record.class_number = @class_numbers.first

    if teacher_absence_blocks_content_record?(@discipline_content_record, @class_numbers)
      set_options_by_user
      flash.now[:alert] = I18n.t('discipline_content_records.create.blocked_by_teacher_absence')
      return render :new
    end

    @class_numbers.each do |class_number|
      @discipline_content_record.class_number = class_number

      return render :new if @discipline_content_record.invalid?
    end

    multiple_content_creator = CreateMultipleContents.new(@class_numbers, @discipline_content_record)

    if multiple_content_creator.call
      if params[:modal] == 'true'
        render html: "<script>window.parent.postMessage({ action: 'closeContentModalAndReload' }, '*');</script>".html_safe, layout: false
      else
        respond_with @discipline_content_record, location: discipline_content_records_path
      end
    else
      set_options_by_user

      render :new
    end
  end

  def parse_record_date(value)
    return nil if value.blank?
    return value.to_date if value.respond_to?(:to_date)
    return Date.parse(value) if value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    return Date.strptime(value.to_s, '%d/%m/%Y') if value.to_s.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z})
    nil
  rescue ArgumentError, TypeError
    nil
  end

  def teacher_absence_blocks_content_record?(discipline_content_record, class_numbers_param = nil)
    return false if current_teacher.blank? || discipline_content_record.blank?

    cr = discipline_content_record.content_record
    return false if cr.blank? || cr.record_date.blank? || cr.classroom_id.blank?

    record_date = cr.record_date.respond_to?(:to_date) ? cr.record_date.to_date : cr.record_date
    class_numbers = if class_numbers_param.present?
                      class_numbers_param.is_a?(String) ? class_numbers_param.split(',').map(&:strip).reject(&:blank?) : Array(class_numbers_param).compact
                    else
                      discipline_content_record.class_number.present? ? [discipline_content_record.class_number] : nil
                    end

    TeacherAbsence.blocks_frequency?(
      classroom_id: cr.classroom_id,
      teacher_id: current_teacher.id,
      absence_date: record_date,
      discipline_id: discipline_content_record.discipline_id.presence,
      class_numbers: class_numbers,
      unity_id: cr.classroom&.unity_id,
      period: nil
    )
  end

  def fetch_discipline_content_records_by_user
    @discipline_content_records =
      apply_scopes(DisciplineContentRecord
        .includes(content_record: [:classroom, :teacher, :contents, :objectives])
        .by_unity_id(current_unity.id)
        .by_classroom_id(@classrooms.map(&:id))
        .by_discipline_id(@disciplines.map(&:id))
        .order_by_classroom
        .ordered)
  end

  def allow_class_number
    begin
      @allow_class_number ||= GeneralConfiguration.first.allow_class_number_on_content_records
    rescue
      @allow_class_number ||= false
    end
  end

  def set_number_of_classes
    @number_of_classes = current_school_calendar.number_of_classes
  end

  def validate_class_numbers
    return true unless allow_class_number
    return true if @class_numbers.present?

    @error_on_class_numbers = true
    flash.now[:alert] = t('errors.daily_frequencies.class_numbers_required_when_not_global_absence')

    false
  end

  def content_ids
    param_content_ids = params[:discipline_content_record][:content_record_attributes][:content_ids] || []
    # Garantir que seja um array mesmo se vier como string vazia
    param_content_ids = [] if param_content_ids.blank?
    # Rejeitar valores vazios, converter para inteiro e rejeitar zeros (IDs inválidos)
    param_content_ids = param_content_ids.reject(&:blank?).map(&:to_i).reject(&:zero?)
    
    # IMPORTANTE: Validar que os IDs são realmente de Content, não de Objective
    # Se um ID de objetivo for enviado por engano, ele será filtrado
    valid_content_ids = param_content_ids.select { |id| Content.exists?(id) }
    if param_content_ids != valid_content_ids
      Rails.logger.warn "=== IDs inválidos filtrados de content_ids: #{(param_content_ids - valid_content_ids).inspect} ==="
      Rails.logger.warn "=== Esses IDs podem ser de Objective ou não existir ==="
    end
    param_content_ids = valid_content_ids
    
    content_descriptions = params[:discipline_content_record][:content_record_attributes][:content_descriptions] || []
    new_contents_ids = content_descriptions.reject(&:blank?).map{|v| Content.find_or_create_by!(description: v).id }
    
    result = (param_content_ids + new_contents_ids).compact.uniq
    result
  end

  def objective_ids
    param_objective_ids = params[:discipline_content_record][:content_record_attributes][:objective_ids] || []
    # Garantir que seja um array mesmo se vier como string vazia
    param_objective_ids = [] if param_objective_ids.blank?
    param_objective_ids = param_objective_ids.reject(&:blank?).map(&:to_i).reject(&:zero?)
    
    # IMPORTANTE: Validar que os IDs são realmente de Objective, não de Content
    # Se um ID de conteúdo for enviado por engano, ele será filtrado
    valid_objective_ids = param_objective_ids.select { |id| Objective.exists?(id) }
    if param_objective_ids != valid_objective_ids
      Rails.logger.warn "=== IDs inválidos filtrados de objective_ids: #{(param_objective_ids - valid_objective_ids).inspect} ==="
      Rails.logger.warn "=== Esses IDs podem ser de Content ou não existir ==="
    end
    param_objective_ids = valid_objective_ids
    
    objective_descriptions =
      params[:discipline_content_record][:content_record_attributes][:objective_descriptions] || []

    @discipline_content_record.content_record.objectives_created_at_position = {}

    param_objective_ids.each_with_index do |objective_id, index|
      @discipline_content_record.content_record.objectives_created_at_position[objective_id.to_i] = index
    end

    new_objectives_ids = objective_descriptions.reject(&:blank?).each_with_index.map { |description, index|
      objective = Objective.find_or_create_by!(description: description)
      @discipline_content_record.content_record.objectives_created_at_position[objective.id] =
        param_objective_ids.size + index

      objective.id
    }

    @ordered_objective_ids = (param_objective_ids + new_objectives_ids).compact.uniq
        
    @ordered_objective_ids
  end

  def resource_params
    params.require(:discipline_content_record).permit(
      :class_number,
      :discipline_id,
      content_record_attributes: [
        :id,
        :unity_id,
        :classroom_id,
        :record_date,
        :daily_activities_record,
        :content,
        :objective
        # NÃO permitir content_ids e objective_ids aqui - são processados pelos métodos content_ids() e objective_ids()
        # para evitar que o Rails processe automaticamente antes de nós sobrescrevermos
      ]
    )
  end

  def clone_params
    params.require(:discipline_content_record_cloner_form).permit(
      :discipline_content_record_id,
      discipline_content_record_item_cloner_form_attributes: [
        :uuid,
        :classroom_id,
        :record_date
      ]
    )
  end

  def contents
    @contents = []
    teacher = current_teacher
    classroom = @discipline_content_record.content_record.classroom
    discipline = @discipline_content_record.discipline
    date = @discipline_content_record.content_record.record_date
    
    # Busca conteúdos dos planos de aula/ensino da disciplina
    plan_contents = []
    if teacher && classroom && discipline && date
      plan_contents = ContentsForDisciplineRecordFetcher.new(teacher, classroom, discipline, date).fetch
      plan_contents.each { |content| content.is_editable = false }
    end
    
    # Busca conteúdos realmente salvos neste registro específico
    # IMPORTANTE: Só busca conteúdos salvos se o DisciplineContentRecord também estiver persistido
    saved_contents = []
    if @discipline_content_record.persisted? && 
       @discipline_content_record.content_record.persisted? && 
       @discipline_content_record.content_record.contents.present?
      saved_contents = @discipline_content_record.content_record.contents_ordered
      saved_contents.each { |content| content.is_editable = true }
    end
    
    # Combina os conteúdos, priorizando os salvos (marcando como editáveis)
    saved_content_ids = saved_contents.map(&:id)
    @contents = plan_contents.map do |content|
      if saved_content_ids.include?(content.id)
        content.is_editable = true
      end
      content
    end
    
    # Adiciona apenas conteúdos salvos que não estão nos planos
    @contents += saved_contents.reject { |content| plan_contents.map(&:id).include?(content.id) }
    
    @contents.uniq
  end
  helper_method :contents

  def all_contents
    Content.ordered
  end
  helper_method :all_contents

  def objectives
    @objectives = []

    teacher = current_teacher
    classroom = @discipline_content_record.content_record.classroom
    discipline = @discipline_content_record.discipline
    date = @discipline_content_record.content_record.record_date
    
    # Busca objetivos dos planos de aula/ensino da disciplina
    plan_objectives = []
    if teacher && classroom && discipline && date
      plan_objectives = ContentsForDisciplineRecordFetcher.new(teacher, classroom, discipline, date).fetch_objectives
      plan_objectives.each { |objective| objective.is_editable = false }
    end

    # Busca objetivos realmente salvos neste registro específico
    # IMPORTANTE: Só busca objetivos salvos se o DisciplineContentRecord também estiver persistido
    saved_objectives = []
    if @discipline_content_record.persisted? && 
       @discipline_content_record.content_record.persisted? && 
       @discipline_content_record.content_record.objectives.present?
      begin
        saved_objectives = @discipline_content_record.content_record.objectives_ordered
        saved_objectives.each { |objective| objective.is_editable = true }
      rescue 
        saved_objectives = []
      end
    end

    # Combina os objetivos, priorizando os salvos (marcando como editáveis)
    saved_objective_ids = saved_objectives.map(&:id)
    @objectives = plan_objectives.map do |objective|
      if saved_objective_ids.include?(objective.id)
        objective.is_editable = true
      end
      objective
    end
    
    # Adiciona objetivos salvos que não estão nos planos
    @objectives += saved_objectives.reject { |objective| plan_objectives.map(&:id).include?(objective.id) }
    
    @objectives.uniq
  end
  helper_method :objectives

  def unities
    @unities = [current_unity]
  end
  helper_method :unities

  def classrooms
    @classrooms = Classroom.by_unity_and_teacher(current_unity.id, current_teacher.id).ordered
  end
  helper_method :classrooms

  def disciplines
    @disciplines = []

    if @discipline_content_record.content_record.classroom.present?
      @disciplines = Discipline.by_teacher_and_classroom(
        current_teacher.id, @discipline_content_record.content_record.classroom.id
      ).ordered
    end

    @disciplines
  end
  helper_method :disciplines

  def set_options_by_user
    # retorna os registros de todas as disciplinas e turmas do professor, somente na visão do professor
    # return fetch_linked_by_teacher unless current_user.current_role_is_admin_or_employee?

    @classrooms ||= [current_user_classroom]
    fetch_linked_by_teacher
    
  end

  def fetch_linked_by_teacher
    @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(current_teacher.id, current_unity, current_school_year, current_user_classroom)
    # @classrooms ||=  @fetch_linked_by_teacher[:classrooms]
    @disciplines ||= @fetch_linked_by_teacher[:disciplines]
  end

  def show_objectives
    Rails.application.secrets.show_objectives.to_s == 'true'
  end
  helper_method :show_objectives

end
