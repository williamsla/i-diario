require 'rails_helper'

RSpec.describe TeachersSynchronizer, type: :service do
  let(:cpf) { '529.982.247-25' }
  let(:unity) { create(:unity, api_code: '9101') }
  let!(:role) { create(:role, :teacher, name: 'Professor') }

  def synchronize(servidor)
    synchronizer = described_class.new(
      synchronization: nil,
      worker_batch: nil,
      worker_state: nil,
      entity_id: nil,
      year: Date.current.year,
      unity_api_code: unity.api_code,
      current_years: [Date.current.year]
    )
    api = instance_double(IeducarApi::Teachers, fetch: { 'servidores' => [servidor] })
    allow(synchronizer).to receive(:api).and_return(api)

    synchronizer.synchronize!
  end

  def servidor_payload(afastamento_ativo:, ativo: 1, servidor_id: '88021')
    {
      'servidor_id' => servidor_id,
      'nome' => 'Maria Souza',
      'cpf' => cpf,
      'ativo' => ativo,
      'afastamento_ativo' => afastamento_ativo,
      'escola_id' => unity.api_code,
      'nm_funcao' => 'Professor'
    }
  end

  describe '#synchronize!' do
    context 'quando o servidor está ativo no cadastro e com afastamento em vigor' do
      let!(:teacher) { create(:teacher, api_code: '88021', name: 'Maria Souza', active: true) }
      let!(:user) do
        create(
          :user,
          teacher: teacher,
          cpf: cpf,
          kind: RoleKind::EMPLOYEE,
          status: UserStatus::ACTIVE,
          first_name: 'Maria',
          last_name: 'Souza'
        )
      end

      it 'marca o professor como inativo e o usuário como pendente' do
        synchronize(servidor_payload(afastamento_ativo: 1))

        expect(teacher.reload.active).to eq(false)
        expect(user.reload.status).to eq(UserStatus::PENDING)
      end
    end

    context 'quando o afastamento já encerrou' do
      let!(:teacher) { create(:teacher, api_code: '88021', name: 'Maria Souza', active: false) }
      let!(:user) do
        create(
          :user,
          teacher: teacher,
          cpf: cpf,
          kind: RoleKind::EMPLOYEE,
          status: UserStatus::PENDING,
          first_name: 'Maria',
          last_name: 'Souza'
        )
      end

      it 'reativa o professor e o usuário' do
        synchronize(servidor_payload(afastamento_ativo: 0))

        expect(teacher.reload.active).to eq(true)
        expect(user.reload.status).to eq(UserStatus::ACTIVE)
      end
    end

    context 'quando o usuário ainda não existe e o afastamento está em vigor' do
      it 'cria o usuário já pendente' do
        synchronize(servidor_payload(afastamento_ativo: 1, servidor_id: '88022'))

        teacher = Teacher.find_by(api_code: '88022')
        user = User.find_by(teacher_id: teacher.id, kind: RoleKind::EMPLOYEE)

        expect(teacher.active).to eq(false)
        expect(user.status).to eq(UserStatus::PENDING)
        expect(user.user_roles.map(&:role_id)).to include(role.id)
      end
    end
  end
end
