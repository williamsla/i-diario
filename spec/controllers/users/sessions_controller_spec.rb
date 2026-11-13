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
