require 'rails_helper'

RSpec.describe SchoolCalendarClassroomsSynchronizer, type: :service do
  let(:synchronization) { create(:ieducar_api_synchronization) }
  let(:worker_batch) { create(:worker_batch) }
  let(:worker_state) { create(:worker_state, worker_batch: worker_batch) }
  let(:unity) { create(:unity) }
  let(:year) { Date.current.year }
  let(:classroom) { create(:classroom, unity: unity, year: year) }
  let!(:school_calendar) { create(:school_calendar, unity: unity, year: year) }
  let(:last_step_end_at) { Date.new(year, 12, 20) }
  let(:expected_end_date_for_posting) { last_step_end_at + 30 }

  let(:api_response) do
    {
      'escolas' => [
        {
          'escola_id' => classroom.unity.api_code,
          'ano' => year,
          'ano_em_aberto' => true,
          'descricao' => 'Bimestre',
          'etapas_de_turmas' => [
            {
              'turma_id' => classroom.api_code,
              'descricao' => 'Bimestre',
              'etapas' => [
                { 'etapa' => 1, 'data_inicio' => "#{year}-02-01", 'data_fim' => "#{year}-04-30" },
                { 'etapa' => 2, 'data_inicio' => "#{year}-05-01", 'data_fim' => "#{year}-07-31" },
                { 'etapa' => 3, 'data_inicio' => "#{year}-08-01", 'data_fim' => "#{year}-10-15" },
                { 'etapa' => 4, 'data_inicio' => "#{year}-10-16", 'data_fim' => last_step_end_at.to_s }
              ]
            }
          ]
        }
      ]
    }
  end

  let(:synchronizer) do
    described_class.new(
      synchronization: synchronization,
      worker_batch: worker_batch,
      worker_state: worker_state,
      year: year,
      unity_api_code: unity.api_code,
      entity_id: create(:entity).id
    )
  end

  before do
    allow(synchronizer).to receive(:api).and_return(double(fetch: api_response))
    allow(SchoolTermTypeUpdaterWorker).to receive(:perform_in)
  end

  describe '#synchronize!' do
    it 'sets end_date_for_posting of all new classroom steps to last step end date plus 30 days' do
      synchronizer.synchronize!

      steps = classroom_steps

      expect(steps.count).to eq(4)
      expect(steps.map(&:end_date_for_posting).uniq).to eq([expected_end_date_for_posting])
    end

    it 'overwrites end_date_for_posting of existing classroom steps to ultima etapa + 30 dias' do
      synchronizer.synchronize!

      custom_end_date = expected_end_date_for_posting + 15
      first_step = classroom_steps.find_by!(step_number: 1)
      first_step.update!(end_date_for_posting: custom_end_date)

      synchronizer.synchronize!

      expect(first_step.reload.end_date_for_posting).to eq(expected_end_date_for_posting)
    end

    it 'uses the latest data_fim even when a higher etapa number ends earlier' do
      api_response['escolas'][0]['etapas_de_turmas'][0]['etapas'] = [
        { 'etapa' => 1, 'data_inicio' => "#{year}-02-01", 'data_fim' => "#{year}-04-30" },
        { 'etapa' => 2, 'data_inicio' => "#{year}-05-01", 'data_fim' => "#{year}-07-24" },
        { 'etapa' => 3, 'data_inicio' => "#{year}-10-08", 'data_fim' => last_step_end_at.to_s },
        { 'etapa' => 4, 'data_inicio' => "#{year}-05-01", 'data_fim' => "#{year}-07-24" }
      ]

      expect { synchronizer.synchronize! }.not_to raise_error

      steps = classroom_steps
      expect(steps.map(&:end_date_for_posting).uniq).to eq([expected_end_date_for_posting])
      expect(steps.find_by!(step_number: 3).start_date_for_posting).to eq(Date.new(year, 10, 8))
    end

    it 'keeps classroom-specific steps instead of overwriting them with school calendar steps' do
      school_calendar.steps.create!(
        step_number: 1,
        start_at: Date.new(year, 2, 23),
        end_at: Date.new(year, 4, 30),
        start_date_for_posting: Date.new(year, 2, 23),
        end_date_for_posting: Date.new(year, 8, 23)
      )
      school_calendar.steps.create!(
        step_number: 2,
        start_at: Date.new(year, 5, 4),
        end_at: Date.new(year, 7, 24),
        start_date_for_posting: Date.new(year, 5, 4),
        end_date_for_posting: Date.new(year, 8, 23)
      )

      school_calendar_classroom = create(
        :school_calendar_classroom,
        classroom: classroom,
        school_calendar: school_calendar
      )
      create(
        :school_calendar_classroom_step,
        school_calendar_classroom: school_calendar_classroom,
        step_number: 1,
        start_at: Date.new(year, 8, 3),
        end_at: Date.new(year, 10, 7),
        start_date_for_posting: Date.new(year, 8, 3),
        end_date_for_posting: Date.new(year, 12, 20)
      )
      second_semester_step = create(
        :school_calendar_classroom_step,
        school_calendar_classroom: school_calendar_classroom,
        step_number: 2,
        start_at: Date.new(year, 10, 8),
        end_at: Date.new(year, 12, 20),
        start_date_for_posting: Date.new(year, 10, 8),
        end_date_for_posting: Date.new(year, 12, 20)
      )

      api_response['escolas'][0]['etapas'] = [
        { 'etapa' => 1, 'data_inicio' => "#{year}-02-23", 'data_fim' => "#{year}-04-30" },
        { 'etapa' => 2, 'data_inicio' => "#{year}-05-04", 'data_fim' => "#{year}-07-24" }
      ]
      api_response['escolas'][0]['etapas_de_turmas'][0]['etapas'] = [
        { 'etapa' => 1, 'data_inicio' => "#{year}-02-23", 'data_fim' => "#{year}-04-30" },
        { 'etapa' => 2, 'data_inicio' => "#{year}-05-04", 'data_fim' => "#{year}-07-24" }
      ]

      expect { synchronizer.synchronize! }.not_to raise_error

      expect(second_semester_step.reload.start_at).to eq(Date.new(year, 10, 8))
      expect(second_semester_step.start_date_for_posting).to eq(Date.new(year, 10, 8))
      expect(classroom_steps.count).to eq(2)
    end
  end

  def classroom_steps
    SchoolCalendarClassroomStep
      .joins(:school_calendar_classroom)
      .where(school_calendar_classrooms: { classroom_id: classroom.id })
      .order(:step_number)
  end
end
