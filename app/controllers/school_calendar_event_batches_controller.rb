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

    if keep_teacher_records?
      destroy_keeping_teacher_records!(school_calendar_event_batch)
    else
      school_calendar_event_batch.update_columns(
        batch_status: BatchStatus::STARTED,
        updated_at: Time.current
      )
      destroy_batch(school_calendar_event_batch.id, false)
    end

    respond_with school_calendar_event_batch, location: school_calendar_event_batches_path
  end

  def reprocess
    school_calendar_event_batch = SchoolCalendarEventBatch.find(params[:id])
    authorize school_calendar_event_batch, :update?

    school_calendar_event_batch.update_columns(
      batch_status: BatchStatus::STARTED,
      error_message: nil,
      updated_at: Time.current
    )

    create_or_update_batch(school_calendar_event_batch.id)

    redirect_to school_calendar_event_batches_path, notice: t('.notice')
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
      :year, :periods, :description, :start_date, :end_date, :event_type, :legend,
      :show_in_frequency_record, :equivalent_weekday
    )

    parameters[:periods] = Array(parameters[:periods]).join(',').split(',').map(&:strip).reject(&:blank?)
    parameters
  end

  def create_or_update_batch(school_calendar_event_batch_id)
    enqueue_or_run_worker(
      SchoolCalendarEventBatchManager::EventCreatorWorker,
      school_calendar_event_batch_id,
      action_name == 'reprocess' ? 'create' : action_name
    )
  end

  def destroy_batch(school_calendar_event_batch_id, keep_teacher_records = false)
    enqueue_or_run_worker(
      SchoolCalendarEventBatchManager::EventDestroyerWorker,
      school_calendar_event_batch_id,
      action_name,
      keep_teacher_records
    )
  end

  def keep_teacher_records?
    params[:keep_teacher_records].to_s == 'true'
  end

  def destroy_keeping_teacher_records!(batch)
    SchoolCalendarEvent.where(batch_id: batch.id).find_each do |event|
      event.keep_teacher_records = true
      event.destroy!
    end

    batch.destroy!
  rescue StandardError => e
    Rails.logger.error("Erro ao excluir evento em lote #{batch.id} mantendo registros: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    batch.mark_with_error!("Erro ao excluir mantendo registros: #{e.message}")
  end

  def enqueue_or_run_worker(worker_class, school_calendar_event_batch_id, worker_action, *extra_args)
    unless current_entity.present?
      error_message = "Entity não encontrada para o domínio #{request.host}"
      Rails.logger.error(error_message)
      mark_batch_with_error(school_calendar_event_batch_id, error_message)
      return
    end

    args = [current_entity.id, school_calendar_event_batch_id, current_user.id, worker_action, *extra_args]

    if sidekiq_process_available?
      worker_class.perform_async(*args)
      Rails.logger.info("Worker #{worker_class} enfileirado no Sidekiq para batch #{school_calendar_event_batch_id}")
    else
      Rails.logger.info("Sidekiq indisponível, executando #{worker_class} de forma síncrona para batch #{school_calendar_event_batch_id}")
      worker_class.new.perform(*args)
    end
  rescue Redis::BaseError, Redis::CannotConnectError => e
    Rails.logger.warn("Redis indisponível (#{e.message}), executando #{worker_class} de forma síncrona")
    worker_class.new.perform(*args)
  rescue StandardError => e
    Rails.logger.error("Erro ao executar #{worker_class} para batch #{school_calendar_event_batch_id}: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    mark_batch_with_error(school_calendar_event_batch_id, "Erro ao executar worker: #{e.message}")
  end

  def sidekiq_process_available?
    require 'sidekiq/api'

    Sidekiq::ProcessSet.new.size.positive?
  rescue StandardError
    false
  end

  def mark_batch_with_error(school_calendar_event_batch_id, error_message)
    batch = SchoolCalendarEventBatch.find(school_calendar_event_batch_id)
    batch.mark_with_error!(error_message)
  rescue StandardError => find_error
    Rails.logger.error("Erro ao marcar batch #{school_calendar_event_batch_id} como erro: #{find_error.message}")
  end

  def school_calendar_event_batch
    @school_calendar_event_batch ||= SchoolCalendarEventBatch.find(params[:id])
  end
end
