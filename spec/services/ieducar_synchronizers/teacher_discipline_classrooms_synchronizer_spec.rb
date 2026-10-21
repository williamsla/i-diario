require 'rails_helper'

RSpec.describe TeacherDisciplineClassroomsSynchronizer, type: :service do
  let(:year) { Date.current.year }
  let(:main_teacher) { create(:teacher, api_code: '1001', name: 'Maria Souza') }
  let(:secondary_teacher) { create(:teacher, api_code: '1002', name: 'Maria Souza') }
  let(:classroom) { create(:classroom, api_code: '301', year: year) }
  let(:discipline) { create(:discipline, api_code: '401') }
  let(:grade) { create(:grade, api_code: '501') }
  let!(:secondary_link) do
    create(
      :teacher_discipline_classroom,
      teacher: secondary_teacher,
      classroom: classroom,
      discipline: discipline,
      grade: grade,
      year: year,
      api_code: '9001'
    )
  end

  before do
    allow(CreateEmptyConceptualExamValueWorker).to receive(:perform_in)
  end

  def synchronize(servidor_id)
    synchronizer = described_class.new(
      synchronization: nil,
      worker_batch: nil,
      worker_state: nil,
      entity_id: nil,
      year: year,
      unity_api_code: '1',
      current_years: [year]
    )
    api = instance_double(
      IeducarApi::TeacherDisciplineClassrooms,
      fetch: { 'vinculos' => [vinculo_payload(servidor_id)] }
    )
    allow(synchronizer).to receive(:api).and_return(api)

    synchronizer.synchronize!
  end

  def vinculo_payload(servidor_id)
    {
      'id' => secondary_link.api_code,
      'servidor_id' => servidor_id,
      'turma_id' => classroom.api_code,
      'turno_id' => classroom.period,
      'permite_lancar_faltas_componente' => 0,
      'updated_at' => Time.zone.parse('2024-05-01 10:00:00'),
      'deleted_at' => nil,
      'disciplinas' => [
        {
          'id' => discipline.api_code,
          'serie_id' => grade.api_code,
          'tipo_nota' => nil
        }
      ]
    }
  end

  describe '#synchronize!' do
    it 'leva a turma para o professor principal quando o i-Educar já trocou o servidor do vínculo' do
      synchronize(main_teacher.api_code)

      expect(secondary_link.reload.teacher_id).to eq(main_teacher.id)
      expect(secondary_link.teacher_api_code).to eq(main_teacher.api_code)
      expect(TeacherDisciplineClassroom.where(teacher_id: secondary_teacher.id)).to be_empty
      expect(Teacher.active).to contain_exactly(main_teacher)
    end

    it 'mantém o horário do quadro apontando para a alocação que permanece' do
      main_link = create(
        :teacher_discipline_classroom,
        teacher: main_teacher,
        classroom: classroom,
        discipline: discipline,
        grade: grade,
        year: year,
        api_code: secondary_link.api_code
      )
      weekday = LessonsBoardLessonWeekday.new(
        teacher_discipline_classroom: secondary_link,
        weekday: '1'
      )
      weekday.save!(validate: false)

      synchronize(main_teacher.api_code)

      expect(weekday.reload.teacher_discipline_classroom_id).to eq(main_link.id)
      expect(secondary_link.reload.discarded_at).to be_present
      expect(main_link.reload.discarded_at).to be_nil
    end

    it 'grava a turma no professor principal quando o vínculo ainda aponta para o servidor unificado' do
      unification = TeacherUnification.create!(teacher: main_teacher, unified_at: Time.current, active: true)
      unification.unified_teachers.create!(teacher: secondary_teacher)

      synchronize(secondary_teacher.api_code)

      expect(secondary_link.reload.teacher_id).to eq(main_teacher.id)
      expect(secondary_link.teacher_api_code).to eq(main_teacher.api_code)
      expect(Teacher.active).to contain_exactly(main_teacher)
    end
  end
end
