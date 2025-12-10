class SchoolCalendarEventBatchesController < ApplicationController
  has_scope :page, default: 1
  has_scope :per, default: 10

  def index
    @school_calendar_event_batches = apply_scopes(SchoolCalendarEventBatch).ordered
    @school_calendar_event_batches = @school_calendar_event_batches.by_year(current_school_year)
    authorize @school_calendar_event_batches
  end

  def new
    @school_calendar_event_batch = SchoolCalendarEventBatch.new

    authorize @school_calendar_event_batch
  end

  def create
    @school_calendar_event_batch = SchoolCalendarEventBatch.new(resource_params)
    @school_calendar_event_batch.batch_status = BatchStatus::STARTED

    authorize @school_calendar_event_batch

    if @school_calendar_event_batch.save
      create_or_update_batch(@school_calendar_event_batch.id)

      respond_with @school_calendar_event_batch, location: school_calendar_event_batches_path
    else
      render :new
    end
  end

  def edit
    @school_calendar_event_batch = SchoolCalendarEventBatch.find(params[:id])

    authorize @school_calendar_event_batch
  end

  def update
    @school_calendar_event_batch = SchoolCalendarEventBatch.find(params[:id])
    @school_calendar_event_batch.assign_attributes(resource_params)
    @school_calendar_event_batch.batch_status = BatchStatus::STARTED

    if @school_calendar_event_batch.save
      create_or_update_batch(@school_calendar_event_batch.id)

      respond_with @school_calendar_event_batch, location: school_calendar_event_batches_path
    else
      render :edit
    end
  end

  def destroy
    school_calendar_event_batch = SchoolCalendarEventBatch.find(params[:id])

    authorize school_calendar_event_batch

    school_calendar_event_batch.update(batch_status: BatchStatus::STARTED)

    destroy_batch(school_calendar_event_batch.id)

    respond_with school_calendar_event_batch, location: school_calendar_event_batches_path
  end

  def school_calendar_years
    years = []

    Unity.with_api_code
         .joins(:school_calendars)
         .pluck('school_calendars.year')
         .uniq
         .compact
         .sort
         .reverse_each do |year|
      years << OpenStruct.new(id: year, text: year, name: year)
    end

    years
  end
  helper_method :school_calendar_years

  private

  def resource_params
    parameters = params.require(:school_calendar_event_batch).permit(
      :year, :periods, :description, :start_date, :end_date, :event_type, :legend, :show_in_frequency_record
    )

    parameters[:periods] = parameters[:periods].split(',')
    parameters
  end

  def create_or_update_batch(school_calendar_event_batch_id)
    # Executa sempre de forma síncrona para garantir que o processamento aconteça imediatamente
    # Isso garante que o status seja atualizado mesmo se o Sidekiq não estiver rodando
    execute_worker_synchronously(school_calendar_event_batch_id)
  end

  def execute_worker_synchronously(school_calendar_event_batch_id)
    Rails.logger.info("=== CONTROLLER: Iniciando execução síncrona do worker para batch #{school_calendar_event_batch_id} ===")
    
    # Verifica se a entidade existe
    unless current_entity.present?
      error_message = "Entity não encontrada para o domínio #{request.host}"
      Rails.logger.error(error_message)
      mark_batch_with_error(school_calendar_event_batch_id, error_message)
      return
    end
    
    entity_id = current_entity.id
    Rails.logger.info("Entity ID: #{entity_id}, Entity Name: #{current_entity.name}")
    
    # Usa a entidade já encontrada pelo current_entity (que busca por domínio)
    # Não precisa verificar novamente, pois se current_entity existe, a entidade existe
    Rails.logger.info("Chamando worker.perform para entity_id=#{entity_id}, batch_id=#{school_calendar_event_batch_id}")
    
    begin
      SchoolCalendarEventBatchManager::EventCreatorWorker.new.perform(
        entity_id,
        school_calendar_event_batch_id,
        current_user.id,
        action_name
      )
      Rails.logger.info("=== CONTROLLER: Worker executado com sucesso para batch #{school_calendar_event_batch_id} ===")
    rescue => e
      Rails.logger.error("=== CONTROLLER: Erro ao executar worker para batch #{school_calendar_event_batch_id}: #{e.class} - #{e.message} ===")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      mark_batch_with_error(school_calendar_event_batch_id, "Erro ao executar worker: #{e.message}")
    end
  end

  def mark_batch_with_error(school_calendar_event_batch_id, error_message)
    begin
      batch = SchoolCalendarEventBatch.find(school_calendar_event_batch_id)
      batch.mark_with_error!(error_message)
    rescue => find_error
      Rails.logger.error("Erro ao marcar batch #{school_calendar_event_batch_id} como erro: #{find_error.message}")
    end
  end

  def destroy_batch(school_calendar_event_batch_id)
    # Executa sempre de forma síncrona para garantir que o processamento aconteça imediatamente
    execute_destroyer_worker_synchronously(school_calendar_event_batch_id)
  end

  def execute_destroyer_worker_synchronously(school_calendar_event_batch_id)
    Rails.logger.info("=== CONTROLLER: Iniciando execução síncrona do destroyer worker para batch #{school_calendar_event_batch_id} ===")
    
    # Verifica se a entidade existe
    unless current_entity.present?
      error_message = "Entity não encontrada para o domínio #{request.host}"
      Rails.logger.error(error_message)
      mark_batch_with_error(school_calendar_event_batch_id, error_message)
      return
    end
    
    entity_id = current_entity.id
    Rails.logger.info("Entity ID: #{entity_id}, Entity Name: #{current_entity.name}")
    
    # Usa a entidade já encontrada pelo current_entity (que busca por domínio)
    # Não precisa verificar novamente, pois se current_entity existe, a entidade existe
    Rails.logger.info("Chamando destroyer worker.perform para entity_id=#{entity_id}, batch_id=#{school_calendar_event_batch_id}")
    
    begin
      SchoolCalendarEventBatchManager::EventDestroyerWorker.new.perform(
        entity_id,
        school_calendar_event_batch_id,
        current_user.id,
        action_name
      )
      Rails.logger.info("=== CONTROLLER: Destroyer worker executado com sucesso para batch #{school_calendar_event_batch_id} ===")
    rescue => e
      Rails.logger.error("=== CONTROLLER: Erro ao executar destroyer worker para batch #{school_calendar_event_batch_id}: #{e.class} - #{e.message} ===")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      mark_batch_with_error(school_calendar_event_batch_id, "Erro ao executar destroyer worker: #{e.message}")
    end
  end

  def school_calendar_event_batch
    @school_calendar_event_batch ||= SchoolCalendarEventBatch.find(params[:id])
  end
end
