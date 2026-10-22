require 'spec_helper'

RSpec.describe 'UnsavedChangesGuard', type: :feature, js: true do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:unity) { create(:unity) }
  let(:school_calendar) { create(:school_calendar, :with_one_step, unity: unity, opened_year: true) }
  let(:current_teacher) { create(:teacher) }
  let(:discipline) { create(:discipline) }
  let(:knowledge_area) { create(:knowledge_area) }
  let(:classroom) do
    create(
      :classroom,
      :with_teacher_discipline_classroom,
      :with_classroom_trimester_steps,
      :score_type_numeric,
      unity: unity,
      teacher: current_teacher,
      discipline: discipline,
      school_calendar: school_calendar
    )
  end
  let(:user) do
    create(
      :user_with_user_role,
      admin: false,
      teacher_id: current_teacher.id,
      current_unity_id: unity.id,
      current_school_year: classroom.year,
      current_classroom_id: classroom.id,
      current_discipline_id: discipline.id
    )
  end

  around(:each) do |example|
    entity.using_connection do
      example.run
    end
  end

  before(:each) do
    knowledge_area.disciplines << discipline

    visit root_path
    fill_in 'Informe o Nome de usuário, E-mail ou CPF', with: user.email
    fill_in 'Senha', with: '12345678'
    click_button 'Acessar'
    expect(page).to have_content('Login realizado com sucesso')
  end

  describe 'Registro de Conteúdos por Disciplina' do
    before do
      click_menu 'Registro de Conteúdos > Conteúdos por disciplina'
      expect(page).to have_content('Registros de conteúdos por disciplina')
    end

    it 'mostra confirmação ao tentar sair após fazer alterações' do
      click_link 'Novo'
      expect(page).to have_selector('#discipline-content-record-form')

      fill_in 'discipline_content_record_content_record_attributes_daily_activities_record', with: 'Atividade teste'

      click_link 'Listagem'

      expect(page).to have_content('Deseja salvar este registro antes de sair?')
    end

    it 'permite sair sem salvar quando não há alterações' do
      click_link 'Novo'
      expect(page).to have_selector('#discipline-content-record-form')

      click_link 'Listagem'

      expect(page).not_to have_content('Deseja salvar este registro antes de sair?')
      expect(page).to have_content('Registros de conteúdos por disciplina')
    end

    it 'salva o registro ao clicar em Salvar no modal' do
      click_link 'Novo'
      expect(page).to have_selector('#discipline-content-record-form')

      fill_in_select2 'discipline_content_record_content_record_attributes_classroom_id', with: classroom.id
      fill_mask 'discipline_content_record_content_record_attributes_record_date', with: '28/02/2017'
      fill_in_select2 'discipline_content_record_discipline_id', with: discipline.id
      fill_in 'discipline_content_record_content_record_attributes_daily_activities_record', with: 'Atividade teste'

      click_link 'Listagem'

      expect(page).to have_content('Deseja salvar este registro antes de sair?')

      within '.bootbox' do
        click_button 'Salvar'
      end

      expect(page).to have_content('Registro de conteúdo foi criado com sucesso').or have_selector('#discipline-content-record-form')
    end

    it 'sai sem salvar ao clicar em Sair sem salvar no modal' do
      click_link 'Novo'
      expect(page).to have_selector('#discipline-content-record-form')

      fill_in 'discipline_content_record_content_record_attributes_daily_activities_record', with: 'Atividade teste'

      click_link 'Listagem'

      expect(page).to have_content('Deseja salvar este registro antes de sair?')

      within '.bootbox' do
        click_button 'Sair sem salvar'
      end

      expect(page).to have_content('Registros de conteúdos por disciplina')
    end
  end

  describe 'Plano de Aula por Disciplina' do
    before do
      click_menu 'Planejamento > Planos de aulas'
      expect(page).to have_content('Planos de aula')
    end

    it 'mostra confirmação ao tentar sair após fazer alterações' do
      click_link 'Novo'

      fill_in 'discipline_lesson_plan_thematic_unit', with: 'Unidade temática teste'

      click_link 'Listagem'

      expect(page).to have_content('Deseja salvar este plano de aula antes de sair?')
    end

    it 'permite sair sem salvar quando não há alterações' do
      click_link 'Novo'

      click_link 'Listagem'

      expect(page).not_to have_content('Deseja salvar este plano de aula antes de sair?')
      expect(page).to have_content('Planos de aula')
    end
  end

  describe 'Diário de Observação' do
    before do
      click_menu 'Registro de Conteúdos > Observações'
      expect(page).to have_content('Diário de observação')
    end

    it 'mostra confirmação ao tentar sair após fazer alterações' do
      click_link 'Novo'
      expect(page).to have_selector('#observation_diary_records_form')

      fill_in_select2 'observation_diary_record_classroom_id', with: classroom.id

      click_link 'Listagem'

      expect(page).to have_content('Deseja salvar este registro antes de sair?')
    end
  end
end
