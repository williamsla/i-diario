require 'rails_helper'

RSpec.describe TeacherUnificationsSynchronizer, type: :service do
  let(:main_teacher) { create(:teacher, api_code: '1001', name: 'Maria Souza') }
  let(:secondary_teacher) { create(:teacher, api_code: '1002', name: 'Maria Souza') }
  let(:classroom_main) { create(:classroom, api_code: '301') }
  let(:classroom_secondary) { create(:classroom, api_code: '302') }
  let!(:main_link) do
    create(:teacher_discipline_classroom, teacher: main_teacher, classroom: classroom_main, api_code: '501')
  end
  let!(:secondary_link) do
    create(:teacher_discipline_classroom, teacher: secondary_teacher, classroom: classroom_secondary, api_code: '502')
  end

  def synchronize(unification)
    synchronizer = described_class.new(
      synchronization: nil,
      worker_batch: nil,
      worker_state: nil,
      entity_id: nil,
      year: Date.current.year,
      unity_api_code: '1',
      current_years: [Date.current.year]
    )
    api = instance_double(IeducarApi::TeacherUnifications, fetch: { 'unificacoes' => [unification] })
    allow(synchronizer).to receive(:api).and_return(api)

    synchronizer.synchronize!
  end

  def unification_payload(duplicates_id:, created_at: '2024-05-01 10:00:00', active: true)
    {
      'main_id' => main_teacher.api_code,
      'duplicates_id' => duplicates_id,
      'created_at' => created_at,
      'active' => active
    }
  end

  describe '#synchronize!' do
    it 'leva o usuário do cadastro duplicado para o professor principal sem apagar a conta' do
      user = create(:user, teacher: secondary_teacher)

      synchronize(unification_payload(duplicates_id: [secondary_teacher.api_code]))

      expect(user.reload.teacher_id).to eq(main_teacher.id)
      expect(User.where(id: user.id)).to exist
      expect(secondary_teacher.reload).to be_discarded
    end

    it 'junta as turmas no professor principal e tira o cadastro duplicado da lista de vínculo' do
      synchronize(unification_payload(duplicates_id: [secondary_teacher.api_code]))

      expect(secondary_teacher.reload).to be_discarded
      expect(main_link.reload.teacher_id).to eq(main_teacher.id)
      expect(secondary_link.reload.teacher_id).to eq(main_teacher.id)
      expect(secondary_link.teacher_api_code).to eq(main_teacher.api_code)
      expect(Teacher.active).to contain_exactly(main_teacher)
    end

    it 'entende duplicates_id quando a API devolve o JSON como texto' do
      synchronize(unification_payload(duplicates_id: "[\"#{secondary_teacher.api_code}\"]"))

      expect(secondary_teacher.reload).to be_discarded
      expect(secondary_link.reload.teacher_id).to eq(main_teacher.id)
    end

    it 'preserva frequência e usuários quando a mesma alocação já existe no professor principal' do
      classroom = create(:classroom, :with_classroom_semester_steps, api_code: '303')
      discipline = create(:discipline, api_code: '403')
      grade = create(:grade, api_code: '503')
      main_allocation = create(
        :teacher_discipline_classroom,
        teacher: main_teacher,
        classroom: classroom,
        discipline: discipline,
        grade: grade,
        year: classroom.year,
        api_code: '8800'
      )
      duplicated_allocation = create(
        :teacher_discipline_classroom,
        teacher: secondary_teacher,
        classroom: classroom,
        discipline: discipline,
        grade: grade,
        year: classroom.year,
        api_code: '8800'
      )
      frequency = build(:daily_frequency, classroom: classroom, teacher: secondary_teacher)
      frequency.save!(validate: false)
      main_user = create(:user, teacher: main_teacher)
      secondary_user = create(:user, teacher: secondary_teacher)

      synchronize(unification_payload(duplicates_id: [secondary_teacher.api_code]))

      expect(frequency.reload.owner_teacher_id).to eq(main_teacher.id)
      expect(DailyFrequency.where(id: frequency.id)).to exist
      expect(main_allocation.reload.discarded_at).to be_nil
      expect(duplicated_allocation.reload.discarded_at).to be_present
      expect(main_user.reload.teacher_id).to eq(main_teacher.id)
      expect(secondary_user.reload.teacher_id).to eq(secondary_teacher.id)
      expect(User.where(id: [main_user.id, secondary_user.id]).count).to eq(2)
      expect(secondary_teacher.reload).not_to be_discarded
    end

    it 'move as turmas de novo quando a unificação já estava gravada e o duplicado continuava ativo' do
      created_at = '2024-05-01 10:00:00'
      TeacherUnification.create!(teacher: main_teacher, unified_at: created_at, active: true)

      unification = HashDecorator.new([unification_payload(duplicates_id: [secondary_teacher.api_code], created_at: created_at)]).first
      probe = TeacherUnification.find_by!(teacher_id: main_teacher.id)
      probe.unified_at = unification.created_at
      probe.active = ActiveRecord::Type::Boolean.new.cast(unification.active)
      expect(probe.changed?).to eq(false)

      synchronize(unification_payload(duplicates_id: [secondary_teacher.api_code], created_at: created_at))

      expect(secondary_teacher.reload).to be_discarded
      expect(secondary_link.reload.teacher_id).to eq(main_teacher.id)
      expect(Teacher.active).to contain_exactly(main_teacher)
    end
  end
end
