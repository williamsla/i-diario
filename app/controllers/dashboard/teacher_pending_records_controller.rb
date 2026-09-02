class Dashboard::TeacherPendingRecordsController < ApplicationController
  before_action :require_current_teacher
  before_action :require_current_classroom

  def index
    if current_user_classroom.blank? || current_teacher.blank?
      return render json: { steps: [], step_data: nil, has_lessons_board: false }
    end

    # Verificar se a turma tem quadro de aulas
    has_lessons_board = LessonsBoard.by_classroom(current_user_classroom.id)
                                    .by_year(current_school_year)
                                    .exists?

    steps_fetcher = StepsFetcher.new(current_user_classroom)
    steps = steps_fetcher.steps

    return render json: { steps: [], step_data: nil, has_lessons_board: has_lessons_board } if steps.blank?

    # Lista de etapas para o seletor do dashboard
    steps_list = steps.map do |step|
      {
        id: step.id,
        name: step.to_s,
        step_number: step.step_number,
        start_at: step.start_at.strftime('%d/%m/%Y'),
        end_at: step.end_at.strftime('%d/%m/%Y'),
        start_at_iso: step.start_at.strftime('%Y-%m-%d'),
        end_at_iso: step.end_at.strftime('%Y-%m-%d')
      }
    end

    # Se step_id foi fornecido, buscar dados apenas dessa etapa
    step_data = nil
    if params[:step_id].present?
      step = steps.find { |s| s.id.to_s == params[:step_id].to_s }
      
      if step
        # Buscar todas as disciplinas do professor na turma atual para esta etapa
        # Usar count_only: true para otimizar e retornar apenas contadores
        calculator = PendingRecordsCalculator.new(
          unity_id: current_unity.id,
          classroom_id: current_user_classroom.id,
          teacher_id: current_teacher.id,
          discipline_id: nil, # nil para buscar todas as disciplinas
          start_date: step.start_at,
          end_date: step.end_at,
          school_year: current_school_year,
          count_only: true,
          include_dates: true # evita chamadas /dates ao expandir: datas já vêm na resposta
        )

        results = calculator.calculate
        show_avaliations_summary = has_numeric_avaliation

        if show_avaliations_summary
          PendingRecordsAvaliationsSummary.new(
            classroom: current_user_classroom,
            start_date: step.start_at,
            end_date: step.end_at,
            pending_records: results
          ).apply!
        end

        # Formatar os resultados para o dashboard (com datas para exibir sem nova requisição)
        # Ordenar por nome da disciplina em ordem alfabética
        pending_records = results.map do |result|
          record = {
            discipline: result[:discipline_name],
            discipline_id: result[:discipline_id] || result[:knowledge_area_id], # Usar knowledge_area_id se discipline_id for nil
            knowledge_area_id: result[:knowledge_area_id], # Para áreas de conhecimento
            final_recovery_discipline_id: result[:discipline_id],
            in_lessons_board: result[:in_lessons_board] != false,
            pending_frequency_count: result[:pending_frequency_count],
            pending_content_count: result[:pending_content_count]
          }
          if show_avaliations_summary
            record[:students_without_note_count] = result[:students_without_note_count] || 0
            record[:students_without_note_from_classroom_total] = result[:students_without_note_from_classroom_total] == true
          end
          if result[:pending_frequency_dates].present? || result[:pending_content_dates].present?
            makeup_dates = result[:optional_holiday_makeup_dates]
            record[:pending_frequency_dates] = format_pending_dates_with_makeup(result[:pending_frequency_dates], makeup_dates)
            record[:pending_content_dates] = format_pending_dates_with_makeup(result[:pending_content_dates], makeup_dates)
          end
          record
        end.reject do |record|
          PendingRecordsCalculator.exclude_pending_record_row?(
            discipline_name: record[:discipline],
            knowledge_area_id: record[:knowledge_area_id],
            discipline_id: record[:discipline_id]
          )
        end.sort_by { |record| record[:discipline] }

        # Frequência por disciplina: quando false, a coluna de frequências deve ser mesclada (um único valor para todas as linhas)
        frequency_type_definer = FrequencyTypeDefiner.new(
          current_user_classroom,
          current_teacher.id,
          nil,
          year: current_school_year
        )
        frequency_type_definer.define!
        frequency_by_discipline = frequency_type_definer.frequency_type == FrequencyTypes::BY_DISCIPLINE

        last_step = last_step?(steps, step)

        step_data = {
          step_id: step.id,
          step_name: step.to_s,
          step_number: step.step_number,
          start_at: step.start_at.strftime('%d/%m/%Y'),
          end_at: step.end_at.strftime('%d/%m/%Y'),
          frequency_by_discipline: frequency_by_discipline,
          has_numeric_avaliation: show_avaliations_summary,
          last_step: last_step,
          show_final_recovery: last_step && PendingRecordsFinalRecoverySummary.available_for?(current_user_classroom),
          pending_records: pending_records
        }
      end
    end

    render json: { steps: steps_list, step_data: step_data, has_lessons_board: has_lessons_board }
  end

  def final_recovery
    return render json: { error: 'Não autorizado' }, status: :unauthorized if current_user_classroom.blank? || current_teacher.blank?

    steps_fetcher = StepsFetcher.new(current_user_classroom)
    steps = steps_fetcher.steps
    step = steps.find { |s| s.id.to_s == params[:step_id].to_s }

    return render json: { error: 'Etapa não encontrada' }, status: :not_found unless step

    unless last_step?(steps, step) && PendingRecordsFinalRecoverySummary.available_for?(current_user_classroom)
      return render json: { counts: {}, errors: {} }
    end

    if current_school_calendar.blank?
      return render json: { counts: {}, errors: {} }
    end

    discipline_ids = params[:discipline_ids].to_s.split(',').map(&:to_i).reject(&:zero?)

    summary = PendingRecordsFinalRecoverySummary.new(
      classroom: current_user_classroom,
      school_calendar: current_school_calendar,
      discipline_ids: discipline_ids
    )

    render json: summary.payload
  end

  def dates
    return render json: { error: 'Parâmetros inválidos' }, status: :bad_request if params[:step_id].blank? || (params[:discipline_id].blank? && params[:knowledge_area_id].blank?)

    return render json: { error: 'Não autorizado' }, status: :unauthorized if current_user_classroom.blank? || current_teacher.blank?

    steps_fetcher = StepsFetcher.new(current_user_classroom)
    steps = steps_fetcher.steps
    step = steps.find { |s| s.id.to_s == params[:step_id].to_s }

    return render json: { error: 'Etapa não encontrada' }, status: :not_found unless step

    # Buscar dados apenas da disciplina ou área de conhecimento específica
    calculator = PendingRecordsCalculator.new(
      unity_id: current_unity.id,
      classroom_id: current_user_classroom.id,
      teacher_id: current_teacher.id,
      discipline_id: params[:discipline_id] || params[:knowledge_area_id], # Aceita ambos
      start_date: step.start_at,
      end_date: step.end_at,
      school_year: current_school_year
    )

    results = calculator.calculate
    result = results.first

    return render json: { error: 'Disciplina/Área de conhecimento não encontrada' }, status: :not_found unless result

    render json: {
      pending_frequency_dates: format_pending_dates_with_makeup(result[:pending_frequency_dates], result[:optional_holiday_makeup_dates]),
      pending_content_dates: format_pending_dates_with_makeup(result[:pending_content_dates], result[:optional_holiday_makeup_dates])
    }
  end

  private

  def last_step?(steps, step)
    last_step = steps.max_by(&:end_at)
    last_step.present? && last_step.id == step.id
  end

  def format_pending_dates_with_makeup(dates, makeup_dates)
    Array(dates).map { |date| OptionalHoliday.format_pending_date(date, makeup_dates) }
  end
end

