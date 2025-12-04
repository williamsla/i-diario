class Dashboard::TeacherPendingRecordsController < ApplicationController
  before_action :require_current_teacher
  before_action :require_current_classroom

  def index
    return render json: { steps: [], step_data: nil } if current_user_classroom.blank? || current_teacher.blank?

    steps_fetcher = StepsFetcher.new(current_user_classroom)
    steps = steps_fetcher.steps

    return render json: { steps: [], step_data: nil } if steps.blank?

    # Retornar lista de steps para o select
    today = Date.current
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
        calculator = PendingRecordsCalculator.new(
          unity_id: current_unity.id,
          classroom_id: current_user_classroom.id,
          teacher_id: current_teacher.id,
          discipline_id: nil, # nil para buscar todas as disciplinas
          start_date: step.start_at,
          end_date: step.end_at,
          school_year: current_school_year
        )

        results = calculator.calculate

        # Formatar os resultados para o dashboard
        pending_records = results.map do |result|
          {
            discipline: result[:discipline_name],
            pending_frequency_count: result[:pending_frequency_count],
            pending_content_count: result[:pending_content_count],
            pending_frequency_dates: result[:pending_frequency_dates].map { |d| d.strftime('%d/%m/%Y') },
            pending_content_dates: result[:pending_content_dates].map { |d| d.strftime('%d/%m/%Y') }
          }
        end

        step_data = {
          step_id: step.id,
          step_name: step.to_s,
          step_number: step.step_number,
          start_at: step.start_at.strftime('%d/%m/%Y'),
          end_at: step.end_at.strftime('%d/%m/%Y'),
          pending_records: pending_records
        }
      end
    end

    render json: { steps: steps_list, step_data: step_data }
  end
end

