# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchoolCalendarPostingDatesController, type: :controller do
  render_views

  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:user) { create(:user, :with_user_role_administrator) }
  let(:year) { Date.current.year }
  let!(:school_calendar) do
    create(
      :school_calendar,
      :with_semester_steps,
      unity: user.user_roles.first.unity,
      year: year,
      step_type_description: 'Semestre'
    )
  end

  around(:each) do |example|
    entity.using_connection { example.run }
  end

  before do
    user.update!(current_school_year: year)
    sign_in(user)
    allow(controller).to receive(:authorize).and_return(true)
    request.env['REQUEST_PATH'] = ''
  end

  describe 'GET #edit' do
    it 'lists the steps of the current school year' do
      get :edit, params: { locale: 'pt-BR' }

      expect(response).to have_http_status(:ok)
      expect(assigns(:groups).map(&:label)).to include('1º Semestre', '2º Semestre')
      expect(response.body).to include('1º Semestre')
    end
  end

  describe 'PATCH #update' do
    let(:new_end_date) { Date.new(year, 8, 20) }

    it 'updates posting dates of the selected step' do
      patch :update, params: {
        locale: 'pt-BR',
        apply_to_classroom_steps: '1',
        groups: {
          '0' => {
            step_number: 1,
            step_type_description: 'Semestre',
            start_date_for_posting: '',
            end_date_for_posting: I18n.l(new_end_date)
          },
          '1' => {
            step_number: 2,
            step_type_description: 'Semestre',
            start_date_for_posting: '',
            end_date_for_posting: ''
          }
        }
      }

      expect(response).to have_http_status(:ok)
      expect(school_calendar.steps.find_by!(step_number: 1).reload.end_date_for_posting).to eq(new_end_date)
      expect(assigns(:result).updated_count).to eq(1)
    end

    it 'does not update when no date is informed' do
      original_end = school_calendar.steps.find_by!(step_number: 1).end_date_for_posting

      patch :update, params: {
        locale: 'pt-BR',
        apply_to_classroom_steps: '1',
        groups: {
          '0' => {
            step_number: 1,
            step_type_description: 'Semestre',
            start_date_for_posting: '',
            end_date_for_posting: ''
          }
        }
      }

      expect(school_calendar.steps.find_by!(step_number: 1).reload.end_date_for_posting).to eq(original_end)
      expect(assigns(:result)).to be_nothing_to_update
    end
  end
end
