require 'spec_helper'

RSpec.describe Users::SessionsController, type: :controller do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:student) { create(:student, name: 'Abner Joaquim Cavalcante Farias') }
  let(:user) do
    role = create(:role, access_level: AccessLevel::STUDENT)
    record = build(
      :user,
      admin: false,
      kind: RoleKind::STUDENT,
      student: student,
      status: UserStatus::ACTIVE,
      receive_news: false,
      first_name: 'ABNER',
      last_name: 'FARIAS',
      email: "#{student.api_code}@STUDENT_DOMAIN",
      login: '52998224725',
      cpf: '529.982.247-25',
      password: 'abner@158',
      password_confirmation: 'abner@158'
    )
    record.save!(validate: false)
    create(:user_role, user: record, role: role, unity: nil)
    record
  end

  before do
    expect(entity).to be_present
    @request.env['devise.mapping'] = Devise.mappings[:user]
  end

  describe 'GET #new' do
    render_views

    def stub_create_users_for_students(enabled)
      configuration = GeneralConfiguration.current
      allow(configuration).to receive(:create_users_for_students_when_synchronize).and_return(enabled)
      allow(GeneralConfiguration).to receive(:current).and_return(configuration)
    end

    it 'oculta a dica da família quando a criação de usuários de alunos está desligada' do
      stub_create_users_for_students(false)

      get :new, params: { locale: 'pt-BR' }

      expect(response.body).not_to include('login-family-hint')
      expect(response.body).not_to include('Sou responsável: como entrar?')
    end

    it 'mostra a dica da família quando a criação de usuários de alunos está ligada' do
      stub_create_users_for_students(true)

      get :new, params: { locale: 'pt-BR' }

      expect(response.body).to include('Sou responsável: como entrar?')
      expect(response.body).to include('login-family-example')
      expect(response.body).to include('joao@123')
      expect(response.body).not_to include('Reenviar instruções de desbloqueio')
    end
  end

  it 'entra no sistema mesmo com o e-mail de aluno inválido' do
    expect(user).not_to be_valid
    expect(user.errors[:email]).to be_present

    post :create, params: {
      locale: 'pt-BR',
      user: { credentials: '529.982.247-25', password: 'abner@158' }
    }

    expect(response).to have_http_status(:redirect)
    expect(response).not_to render_template(:new)
    expect(controller.current_user).to eq(user)
  end
end
