# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionalHolidaysController, type: :controller do
  render_views

  let(:entity) { Entity.find_by(domain: 'test.host') }
  around(:each) do |example|
    entity.using_connection do
      example.run
    end
  end

  let(:unity) { create(:unity) }
  let(:school_calendar) { create(:school_calendar, :with_one_step, unity: unity, opened_year: true) }
  let(:user) { create(:user, :with_user_role_administrator, current_unity_id: unity.id, current_school_year: school_calendar.year) }

  before do
    sign_in(user)
    allow(controller).to receive(:authorize).and_return(true)
    allow(controller).to receive(:require_allow_to_modify_prev_years).and_return(true)
    allow(controller).to receive(:current_unity).and_return(unity)
    allow(controller).to receive(:current_school_year).and_return(school_calendar.year)
    request.env['REQUEST_PATH'] = '/pontos-facultativos'
  end

  describe 'GET #index' do
    it 'lists holidays of the current year' do
      matching = create(:optional_holiday, year: school_calendar.year, user: user)
      other = create(:optional_holiday, year: school_calendar.year - 1, holiday_date: Date.new(school_calendar.year - 1, 3, 1), user: user)

      get :index, params: { locale: 'pt-BR' }

      expect(assigns(:optional_holidays)).to include(matching)
      expect(assigns(:optional_holidays)).not_to include(other)
    end
  end

  describe 'POST #create' do
    it 'creates a holiday and syncs calendar events' do
      expect_any_instance_of(OptionalHolidayCalendarSynchronizer).to receive(:sync)

      expect {
        post :create, params: {
          locale: 'pt-BR',
          optional_holiday: {
            holiday_date: Date.current,
            description: 'Decreto municipal',
            makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL,
            periods: %w[1 2]
          }
        }
      }.to change(OptionalHoliday, :count).by(1)

      expect(response).to redirect_to(optional_holidays_path)
    end
  end

  describe 'PATCH #update' do
    it 'updates the municipal make up date' do
      holiday = create(
        :optional_holiday,
        year: school_calendar.year,
        user: user,
        makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL
      )
      allow_any_instance_of(OptionalHolidayCalendarSynchronizer).to receive(:sync)

      patch :update, params: {
        locale: 'pt-BR',
        id: holiday.id,
        optional_holiday: {
          holiday_date: I18n.l(holiday.holiday_date),
          description: holiday.description,
          makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL,
          make_up_date: I18n.l(holiday.holiday_date + 3.days),
          periods: holiday.periods
        }
      }

      expect(holiday.reload.make_up_date).to eq(holiday.holiday_date + 3.days)
      expect(response).to redirect_to(optional_holidays_path)
    end

    it 'uses the holiday weekday as Saturday make up reference without asking for it' do
      friday = Date.new(school_calendar.year, 8, 1)
      friday += 1 until friday.friday?
      saturday = friday + 1

      holiday = create(
        :optional_holiday,
        year: school_calendar.year,
        user: user,
        holiday_date: friday,
        makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL
      )
      allow_any_instance_of(OptionalHolidayCalendarSynchronizer).to receive(:sync)

      patch :update, params: {
        locale: 'pt-BR',
        id: holiday.id,
        optional_holiday: {
          holiday_date: I18n.l(holiday.holiday_date),
          description: holiday.description,
          makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL,
          make_up_date: I18n.l(saturday),
          periods: holiday.periods
        }
      }

      holiday.reload
      expect(holiday.make_up_date).to eq(saturday)
      expect(holiday.equivalent_weekday).to eq(Workdays::FRIDAY)
    end
  end
end
