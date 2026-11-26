# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserAccessReportsController, type: :controller do
  render_views

  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:user) { create(:user, :with_user_role_administrator) }
  let(:teacher_role) { create(:role, :teacher, name: 'Professor da turma') }
  let(:school) { create(:unity, name: 'Escola Central') }

  around(:each) do |example|
    entity.using_connection { example.run }
  end

  before do
    sign_in(user)
    request.env['REQUEST_PATH'] = ''
  end

  def grant_access_report(target_user, permission = Permissions::READ)
    role = target_user.current_user_role.role
    role.permissions.find_or_initialize_by(feature: 'user_access_reports').tap do |role_permission|
      role_permission.permission = permission
      role_permission.save_without_auditing
    end
    target_user.reload
  end

  describe 'GET #index' do
    it 'lists accesses of the selected profile by school' do
      grant_access_report(user)
      teacher = create(:user)
      create(:user_role, user: teacher, role: teacher_role, unity: school)
      UserLogin.create!(user: teacher, sign_in_ip: '127.0.0.1')

      get :index, params: { locale: 'pt-BR', role_id: teacher_role.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Professor da turma')
      expect(response.body).to include('Escola Central')
      expect(response.body).to include('Geral')
    end

    it 'asks for a profile before showing numbers' do
      grant_access_report(user)

      get :index, params: { locale: 'pt-BR' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Selecione um perfil para ver os acessos.')
      expect(response.body).not_to include('Geral')
    end

    it 'redirects an administrator without the permission' do
      get :index, params: { locale: 'pt-BR' }

      expect(response).to redirect_to(root_path)
    end

    it 'shows an employee only the accesses of the current school' do
      employee = create(:user, :with_user_role_employee)
      own_school = employee.current_user_role.unity
      employee.update!(current_unity_id: own_school.id)
      other_school = create(:unity, name: 'Outra Escola')
      student_role = create(:role, name: 'Estudante do portal', access_level: AccessLevel::STUDENT)
      student = create(:user)
      create(:user_role, user: student, role: student_role, unity: own_school)
      create(:user_role, user: student, role: student_role, unity: other_school)
      UserLogin.create!(user: student, sign_in_ip: '127.0.0.1')
      grant_access_report(employee)
      sign_in(employee)

      get :index, params: { locale: 'pt-BR', role_id: student_role.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(own_school.name)
      expect(response.body).not_to include('Outra Escola')
      expect(response.body).not_to include('Professor da turma')
    end

    it 'redirects a teacher even with the permission' do
      teacher = create(:user, :with_user_role_teacher)
      grant_access_report(teacher)
      sign_in(teacher)

      get :index, params: { locale: 'pt-BR' }

      expect(response).to redirect_to(root_path)
    end
  end
end
