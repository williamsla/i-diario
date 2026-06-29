class KnowledgeAreaContentRecordsController < ApplicationController
  include LessonsBoardAvailability

  has_scope :page, default: 1
  has_scope :per, default: 10

  before_action :require_current_classroom, only: [:index, :new, :edit, :create, :update]
  before_action :require_current_teacher
  before_action :require_current_classroom, only: [:index, :new, :create, :edit, :update, :show]
  before_action :require_allow_to_modify_prev_years, only: [:create, :update, :destroy, :clone]

  def knowledge_areas_for_record_date
    classroom_id = params[:classroom_id].presence || current_user_classroom&.id
    record_date = parse_lessons_board_date(params[:record_date])

    if classroom_id.blank? || record_date.blank?
      render json: { knowledge_areas: [], message: nil }
      return
    end

    authorize KnowledgeAreaContentRecord.new, :new?

    classroom = Classroom.find_by(id: classroom_id)
    if classroom.blank?
      render json: { knowledge_areas: [], message: nil }
      return
    end

    result = build_knowledge_areas_for_content_record_result(
      classroom: classroom,
      record_date: record_date
    )

    render json: {
      knowledge_areas: result[:knowledge_areas].map { |ka| { id: ka.id, description: ka.description } },
      message: result[:message]
    }
  end

  def index
    params[:filter] ||= {}
    author_type = PlansAuthors::MY_PLANS.to_s if params[:filter].empty?
    author_type ||= (params[:filter] || []).delete(:by_author)

    set_options_by_user
    set_knowledge_area_by_classroom(@classrooms.map(&:id))

    @knowledge_area_content_records = fetch_knowledge_area_content_records_by_user

    if author_type.present?
      @knowledge_area_content_records = @knowledge_area_content_records.by_author(author_type, current_teacher.id)
    end

    authorize @knowledge_area_content_records
  end

  def show
    @knowledge_area_content_record = KnowledgeAreaContentRecord.find(params[:id]).localized

    set_options_by_user
    set_knowledge_area_by_classroom(@knowledge_area_content_record.classroom_id)

    authorize @knowledge_area_content_record
  end

  def new
    set_options_by_user

    @knowledge_area_content_record = KnowledgeAreaContentRecord.new.localized

    # verifica se o usuário passou o parametro da área de conhecimento na URL. Normalmente usado em modal
    if params[:knowledge_area_id].present?
      @knowledge_area_content_record.knowledge_area_ids = [params[:knowledge_area_id]]
    end

    @knowledge_area_content_record.content_record ||= ContentRecord.new

    if params[:recorded_at].present?
      record_date = Date.parse(params[:recorded_at])
    else
      record_date = Time.zone.now
    end

    @knowledge_area_content_record.build_content_record(
      record_date: record_date,
      unity_id: current_unity.id,
      classroom_id: current_user_classroom.id
    )

    set_knowledge_area_by_classroom(current_user_classroom.id)

    if params[:modal] != 'true'
      availability = build_knowledge_areas_for_content_record_result(
        classroom: current_user_classroom,
        record_date: record_date.to_date
      )
      @knowledge_areas = availability[:knowledge_areas]
      @record_date_message = availability[:message]
    end

    authorize @knowledge_area_content_record
  end

  def create
    @knowledge_area_content_record = KnowledgeAreaContentRecord.new(resource_params)
    @knowledge_area_content_record.knowledge_area_ids = parsed_knowledge_area_ids
    @knowledge_area_content_record.content_record.teacher = current_teacher
    @knowledge_area_content_record.content_record.content_ids = content_ids
    @knowledge_area_content_record.content_record.objective_ids = objective_ids
    @knowledge_area_content_record.content_record.origin = OriginTypes::WEB
    @knowledge_area_content_record.content_record.creator_type = 'knowledge_area_content_record'
    @knowledge_area_content_record.content_record.teacher = current_teacher
    @knowledge_area_content_record.teacher_id = current_teacher_id

    authorize @knowledge_area_content_record

    # Usa transação para garantir atomicidade e evitar condições de corrida
    saved = false
    begin
      ActiveRecord::Base.transaction do
        # Valida antes de salvar para capturar erros
        unless @knowledge_area_content_record.valid?
          Rails.logger.error "=== Erros de validação antes do save: #{@knowledge_area_content_record.errors.full_messages.inspect} ==="
          Rails.logger.error "=== Content Record errors: #{@knowledge_area_content_record.content_record.errors.full_messages.inspect} ==="
          raise ActiveRecord::RecordInvalid.new(@knowledge_area_content_record) unless @knowledge_area_content_record.errors.empty?
        end

        saved = @knowledge_area_content_record.save
        
        # Verifica se realmente foi salvo
        unless saved && @knowledge_area_content_record.persisted?
          Rails.logger.error "=== Save falhou ou registro não foi persistido ==="
          Rails.logger.error "=== Erros: #{@knowledge_area_content_record.errors.full_messages.inspect} ==="
          Rails.logger.error "=== Content Record errors: #{@knowledge_area_content_record.content_record.errors.full_messages.inspect} ==="
          raise ActiveRecord::RecordInvalid.new(@knowledge_area_content_record)
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
        render html: "<script type='text/javascript'>window.parent.postMessage({ action: 'closeContentModalAndReload' }, '*');</script>".html_safe, layout: false
      else
        respond_with @knowledge_area_content_record, location: knowledge_area_content_records_path
      end
    else
      error_messages = @knowledge_area_content_record.errors.full_messages
      content_record_errors = @knowledge_area_content_record.content_record.errors.full_messages
      
      Rails.logger.error "=== Falha ao salvar registro ==="
      Rails.logger.error "=== KnowledgeAreaContentRecord errors: #{error_messages.inspect} ==="
      Rails.logger.error "=== ContentRecord errors: #{content_record_errors.inspect} ==="
      
      # Adiciona mensagem de erro ao flash se houver erros
      all_errors = (error_messages + content_record_errors).compact
      if all_errors.any?
        flash.now[:alert] = all_errors.join(', ')
      else
        flash.now[:alert] = 'Não foi possível salvar o registro. Por favor, tente novamente.'
      end
      
      set_options_by_user
      set_knowledge_area_by_classroom(@knowledge_area_content_record.classroom_id)
      render :new
    end
  end

  def edit
    @knowledge_area_content_record = KnowledgeAreaContentRecord.find(params[:id]).localized

    set_options_by_user
    set_knowledge_area_by_classroom(@knowledge_area_content_record.classroom_id)

    authorize @knowledge_area_content_record
  end

  def update
    @knowledge_area_content_record = KnowledgeAreaContentRecord.find(params[:id])
    @knowledge_area_content_record.assign_attributes(resource_params)
    @knowledge_area_content_record.knowledge_area_ids = parsed_knowledge_area_ids
    @knowledge_area_content_record.content_record.content_ids = content_ids
    @knowledge_area_content_record.content_record.objective_ids = objective_ids
    @knowledge_area_content_record.teacher_id = current_teacher_id
    @knowledge_area_content_record.content_record.current_user = current_user

    authorize @knowledge_area_content_record

    # Usa transação para garantir atomicidade e evitar condições de corrida
    saved = false
    begin
      ActiveRecord::Base.transaction do
        # Valida antes de salvar para capturar erros
        unless @knowledge_area_content_record.valid?
          Rails.logger.error "=== Erros de validação antes do save (update): #{@knowledge_area_content_record.errors.full_messages.inspect} ==="
          Rails.logger.error "=== Content Record errors: #{@knowledge_area_content_record.content_record.errors.full_messages.inspect} ==="
          raise ActiveRecord::RecordInvalid.new(@knowledge_area_content_record) unless @knowledge_area_content_record.errors.empty?
        end

        saved = @knowledge_area_content_record.save
        
        # Verifica se realmente foi salvo
        unless saved && @knowledge_area_content_record.persisted?
          Rails.logger.error "=== Save falhou ou registro não foi persistido (update) ==="
          Rails.logger.error "=== Erros: #{@knowledge_area_content_record.errors.full_messages.inspect} ==="
          Rails.logger.error "=== Content Record errors: #{@knowledge_area_content_record.content_record.errors.full_messages.inspect} ==="
          raise ActiveRecord::RecordInvalid.new(@knowledge_area_content_record)
        end

      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "=== Exceção ao atualizar: #{e.message} ==="
      saved = false
    rescue => e
      Rails.logger.error "=== Erro inesperado ao atualizar: #{e.class} - #{e.message} ==="
      Rails.logger.error e.backtrace.join("\n")
      saved = false
    end

    if saved
      if params[:modal] == 'true'
        render html: "<script type='text/javascript'>window.parent.postMessage({ action: 'closeContentModalAndReload' }, '*');</script>".html_safe, layout: false
      else
        respond_with @knowledge_area_content_record, location: knowledge_area_content_records_path
      end
    else
      error_messages = @knowledge_area_content_record.errors.full_messages
      content_record_errors = @knowledge_area_content_record.content_record.errors.full_messages
      
      Rails.logger.error "=== Falha ao atualizar registro ==="
      Rails.logger.error "=== KnowledgeAreaContentRecord errors: #{error_messages.inspect} ==="
      Rails.logger.error "=== ContentRecord errors: #{content_record_errors.inspect} ==="
      
      # Adiciona mensagem de erro ao flash se houver erros
      all_errors = (error_messages + content_record_errors).compact
      if all_errors.any?
        flash.now[:alert] = all_errors.join(', ')
      else
        flash.now[:alert] = 'Não foi possível atualizar o registro. Por favor, tente novamente.'
      end
      
      set_options_by_user
      set_knowledge_area_by_classroom(@knowledge_area_content_record.classroom_id)

      render :edit
    end
  end

  def destroy
    @knowledge_area_content_record = KnowledgeAreaContentRecord.find(params[:id]).localized

    authorize @knowledge_area_content_record

    @knowledge_area_content_record.destroy

    respond_with @knowledge_area_content_record, location: knowledge_area_content_records_path
  end

  def history
    @knowledge_area_content_record = KnowledgeAreaContentRecord.find(params[:id])

    authorize @knowledge_area_content_record

    respond_with @knowledge_area_content_record
  end

  def clone
    @form = KnowledgeAreaContentRecordClonerForm.new(clone_params.merge(teacher: current_teacher))

    flash[:success] = t('messages.copy_succeed') if @form.clone!
  end

  private

  def fetch_knowledge_area_content_records_by_user
    apply_scopes(KnowledgeAreaContentRecord
      .includes(:knowledge_areas, content_record: [:classroom, :teacher, :student, :contents, :objectives])
      .by_classroom_id(@classrooms.map(&:id))
      .order_by_classroom
      .ordered)
  end

  def content_ids
    param_content_ids = params[:knowledge_area_content_record][:content_record_attributes][:content_ids] || []
    content_descriptions = params[:knowledge_area_content_record][:content_record_attributes][:content_descriptions] || []
    new_contents_ids = content_descriptions.map { |content_description|
      Content.find_or_create_by!(description: content_description).id
    }
    param_content_ids + new_contents_ids
  end

  def objective_ids
    param_objective_ids = params[:knowledge_area_content_record][:content_record_attributes][:objective_ids] || []
    objective_descriptions =
      params[:knowledge_area_content_record][:content_record_attributes][:objective_descriptions] || []

    @knowledge_area_content_record.content_record.objectives_created_at_position = {}

    param_objective_ids.each_with_index do |objective_id, index|
      @knowledge_area_content_record.content_record.objectives_created_at_position[objective_id.to_i] = index
    end

    new_objectives_ids = objective_descriptions.each_with_index.map { |description, index|
      objective = Objective.find_or_create_by!(description: description)
      @knowledge_area_content_record.content_record.objectives_created_at_position[objective.id] =
        param_objective_ids.size + index

      objective.id
    }

    @ordered_objective_ids = param_objective_ids + new_objectives_ids
  end

  def parsed_knowledge_area_ids
    ids = resource_params[:knowledge_area_ids]
    return [] if ids.blank?

    ids.is_a?(Array) ? ids.map(&:to_s) : ids.split(',')
  end

  def resource_params
    params.require(:knowledge_area_content_record).permit(
      :knowledge_area_ids,
      :experience_fields,
      content_record_attributes: [
        :id,
        :unity_id,
        :classroom_id,
        :record_date,
        :daily_activities_record,
        :student_id,
        :content_ids,
        :objective_ids
      ]
    )
  end

  def clone_params
    params.require(:knowledge_area_content_record_cloner_form).permit(
      :knowledge_area_content_record_id,
      knowledge_area_content_record_item_cloner_form_attributes: [
        :uuid,
        :classroom_id,
        :record_date
      ]
    )
  end

  def contents
    @contents = []
    teacher = current_teacher
    classroom = @knowledge_area_content_record.content_record.classroom
    knowledge_areas = @knowledge_area_content_record.knowledge_areas
    date = @knowledge_area_content_record.content_record.record_date
    
    # Busca conteúdos dos planos de aula/ensino da área de conhecimento
    plan_contents = []
    student_id = @knowledge_area_content_record.content_record.student_id

    if teacher && classroom && knowledge_areas && date
      plan_contents = ContentsForKnowledgeAreaRecordFetcher.new(
        teacher, classroom, knowledge_areas, date, student_id
      ).fetch
      plan_contents.each { |content| content.is_editable = false }
    end
    
    # Busca conteúdos realmente salvos neste registro específico
    # IMPORTANTE: Só busca conteúdos salvos se o KnowledgeAreaContentRecord também estiver persistido
    saved_contents = []
    if @knowledge_area_content_record.persisted? && 
       @knowledge_area_content_record.content_record.persisted? && 
       @knowledge_area_content_record.content_record.contents.present?
      saved_contents = @knowledge_area_content_record.content_record.contents_ordered
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
    classroom = @knowledge_area_content_record.content_record.classroom
    knowledge_areas = @knowledge_area_content_record.knowledge_areas
    date = @knowledge_area_content_record.content_record.record_date
    
    # Busca objetivos dos planos de aula/ensino da área de conhecimento
    plan_objectives = []
    student_id = @knowledge_area_content_record.content_record.student_id

    if teacher && classroom && knowledge_areas && date
      plan_objectives = ContentsForKnowledgeAreaRecordFetcher.new(
        teacher, classroom, knowledge_areas, date, student_id
      ).fetch_objectives
      plan_objectives.each { |objective| objective.is_editable = false }
    end

    # Busca objetivos realmente salvos neste registro específico
    # IMPORTANTE: Só busca objetivos salvos se o KnowledgeAreaContentRecord também estiver persistido
    saved_objectives = []
    if @knowledge_area_content_record.persisted? && 
       @knowledge_area_content_record.content_record.persisted? && 
       @knowledge_area_content_record.content_record.objectives.present?
      begin
        saved_objectives = @knowledge_area_content_record.content_record.objectives_ordered
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

  def set_options_by_user
    fetch_students_with_disabilities
    @classrooms = [current_user_classroom]
  end

  def student_enrollments
    StudentEnrollmentsList.new(
      classroom: current_user_classroom,
      discipline: current_user_discipline,
      search_type: :by_year
    ).student_enrollments
  end

  def fetch_students_with_disabilities
    @students = []

    @student_enrollments ||= student_enrollments

    @student_ids = @student_enrollments.collect(&:student_id)

    if is_aee == true
      @students = Student.where(id: @student_ids).ordered
    else
      @students = Student.where(id: @student_ids).where(uses_differentiated_exam_rule: true).ordered
    end
  end

  def set_knowledge_area_by_classroom(classroom_id)
    classroom = Classroom.find_by(id: classroom_id)

    knowledge_areas = if multigrade_infantil_fundamental_classroom?(classroom)
                        infantil_discipline_ids = discipline_ids_for_grade_ids(
                          classroom,
                          infantil_grade_ids(classroom)
                        )
                        KnowledgeArea.by_teacher(current_teacher)
                                     .by_discipline_id(infantil_discipline_ids)
                                     .ordered
                      else
                        KnowledgeArea.by_teacher(current_teacher)
                                     .by_classroom_id(classroom_id)
                                     .ordered
                      end

    @knowledge_areas = filter_knowledge_areas_for_content_registration(knowledge_areas, classroom)
  end

  def fetch_linked_by_teacher
    @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(current_teacher.id, current_unity, current_school_year)
    @classrooms ||=  @fetch_linked_by_teacher[:classrooms]
    @disciplines ||= @fetch_linked_by_teacher[:disciplines]
  end
  
  def show_objectives
    Rails.application.secrets.show_objectives.to_s == 'true'
  end
  helper_method :show_objectives
end
