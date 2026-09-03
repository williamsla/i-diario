require 'rails_helper'

RSpec.describe SchoolCalendarsSynchronizer, type: :service do
  let(:synchronization) { create(:ieducar_api_synchronization) }
  let(:worker_batch) { create(:worker_batch) }
  let(:worker_state) { create(:worker_state, worker_batch: worker_batch) }
  let(:unity) { create(:unity) }
  let(:year) { Date.current.year }
  let(:entity_id) { create(:entity).id }
  let(:school_calendar) { create(:school_calendar, unity: unity, year: year) }

  let(:step_end_date_for_posting) { last_step_end_at + 30 }
  let(:last_step_end_at) { Date.new(year, 12, 20) }

  let(:steps_from_api) do
    [
      OpenStruct.new(etapa: 1, data_inicio: Date.new(year, 2, 1), data_fim: Date.new(year, 4, 30)),
      OpenStruct.new(etapa: 2, data_inicio: Date.new(year, 5, 1), data_fim: Date.new(year, 7, 31)),
      OpenStruct.new(etapa: 3, data_inicio: Date.new(year, 8, 1), data_fim: Date.new(year, 10, 15)),
      OpenStruct.new(etapa: 4, data_inicio: Date.new(year, 10, 16), data_fim: last_step_end_at)
    ]
  end

  let(:synchronizer) do
    described_class.new(
      synchronization: synchronization,
      worker_batch: worker_batch,
      worker_state: worker_state,
      year: year,
      unity_api_code: unity.api_code,
      entity_id: entity_id
    )
  end

  before do
    synchronizer.instance_variable_set(:@school_calendar_steps_ids, [])
    synchronizer.instance_variable_set(:@changed_steps, false)
  end

  it 'define end_date_for_posting de todas as etapas como a ultima etapa + 30 dias (quando cria)' do
    synchronizer.send(:update_or_create_steps, steps_from_api, school_calendar.id)

    steps = SchoolCalendarStep.where(school_calendar_id: school_calendar.id).order(:step_number)

    expect(steps.size).to eq(4)
    expect(steps.map(&:end_date_for_posting).uniq).to eq([step_end_date_for_posting])
  end

  it 'ajusta end_date_for_posting existente para ultima etapa + 30 dias quando estiver invalida' do
    SchoolCalendarStep.create!(
      school_calendar: school_calendar,
      step_number: 1,
      start_at: Date.new(year, 2, 1),
      end_at: Date.new(year, 4, 30),
      start_date_for_posting: Date.new(year, 2, 1),
      end_date_for_posting: Date.new(year, 4, 1) # menor que end_at, deve ser corrigida
    )

    synchronizer.send(:update_or_create_steps, steps_from_api, school_calendar.id)

    expect(
      SchoolCalendarStep.find_by!(school_calendar_id: school_calendar.id, step_number: 1).end_date_for_posting
    ).to eq(step_end_date_for_posting)
  end
end

