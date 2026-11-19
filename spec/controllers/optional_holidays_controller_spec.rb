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

    context 'when the user is a school employee' do
      let(:employee) do
        create(:user, :with_user_role_employee, admin: false, current_unity_id: unity.id, current_school_year: school_calendar.year)
      end

      before do
        role = employee.current_user_role.role
        role.permissions.find_or_initialize_by(feature: 'optional_holidays').tap do |permission|
          permission.permission = Permissions::CHANGE
          permission.save_without_auditing
        end
        employee.reload
        employee.current_user_role = employee.user_roles.first
        sign_in(employee)
        allow(controller).to receive(:current_user).and_return(employee)
      end

      it 'shows the update makeup button when the school already informed the date' do
        holiday = create(
          :optional_holiday,
          year: school_calendar.year,
          user: user,
          makeup_scope: OptionalHolidayMakeupScope::BY_SCHOOL
        )
        create(
          :optional_holiday_unity_makeup,
          optional_holiday: holiday,
          unity: unity,
          make_up_date: holiday.holiday_date + 2.days
        )

        get :index, params: { locale: 'pt-BR' }

        expect(response.body).to include('Atualizar data de reposição')
        expect(response.body).not_to include('Informar data de reposição da escola')
      end

      it 'shows the inform makeup button when the date is still pending' do
        create(
          :optional_holiday,
          year: school_calendar.year,
          user: user,
          makeup_scope: OptionalHolidayMakeupScope::BY_SCHOOL
        )

        get :index, params: { locale: 'pt-BR' }

        expect(response.body).to include('Informar data de reposição da escola')
      end
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

    it 'saves a different municipal makeup date for a course' do
      course = create(:course, description: 'Fundamental')
      course_classroom = create(:classroom, unity: unity, year: school_calendar.year, period: Periods::VESPERTINE)
      create(:classrooms_grade, classroom: course_classroom, grade: create(:grade, course: course))
      holiday = create(
        :optional_holiday,
        year: school_calendar.year,
        user: user,
        holiday_date: Date.new(school_calendar.year, 4, 2),
        makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL
      )
      allow_any_instance_of(OptionalHolidayCalendarSynchronizer).to receive(:sync)
      course_date = holiday.holiday_date + 4.days

      patch :update, params: {
        locale: 'pt-BR',
        id: holiday.id,
        optional_holiday: {
          holiday_date: I18n.l(holiday.holiday_date),
          description: holiday.description,
          makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL,
          make_up_date: I18n.l(holiday.holiday_date + 2.days),
          periods: holiday.periods,
          course_makeups: {
            course.id.to_s => { course_id: course.id, make_up_date: I18n.l(course_date) }
          }
        }
      }

      expect(response).to redirect_to(optional_holidays_path)
      expect(holiday.reload.make_up_date).to eq(holiday.holiday_date + 2.days)
      expect(holiday.make_up_date_for(unity.id, course_id: course.id)).to eq(course_date)
    end

    context 'when the user is a school employee' do
      let(:employee) do
        create(:user, :with_user_role_employee, admin: false, current_unity_id: unity.id, current_school_year: school_calendar.year)
      end
      let(:holiday) do
        create(
          :optional_holiday,
          year: school_calendar.year,
          user: user,
          makeup_scope: OptionalHolidayMakeupScope::BY_SCHOOL
        )
      end

      before do
        sign_in(employee)
        allow(controller).to receive(:current_user).and_return(employee)
      end

      it 'saves only the school makeup date' do
        allow_any_instance_of(OptionalHolidayCalendarSynchronizer).to receive(:sync)
        original_description = holiday.description

        patch :update, params: {
          locale: 'pt-BR',
          id: holiday.id,
          optional_holiday: {
            description: 'Tentativa de alterar o decreto',
            make_up_date: I18n.l(holiday.holiday_date + 3.days)
          }
        }

        holiday.reload
        expect(holiday.description).to eq(original_description)
        expect(holiday.make_up_date_for(unity.id)).to eq(holiday.holiday_date + 3.days)
        expect(response).to redirect_to(optional_holidays_path)
      end

      it 'updates a makeup date that was already informed' do
        informed_date = holiday.holiday_date + 2.days
        create(
          :optional_holiday_unity_makeup,
          optional_holiday: holiday,
          unity: unity,
          make_up_date: informed_date
        )
        allow_any_instance_of(OptionalHolidayCalendarSynchronizer).to receive(:sync)

        patch :update, params: {
          locale: 'pt-BR',
          id: holiday.id,
          optional_holiday: {
            make_up_date: I18n.l(holiday.holiday_date + 5.days)
          }
        }

        expect(holiday.reload.make_up_date_for(unity.id)).to eq(holiday.holiday_date + 5.days)
        expect(response).to redirect_to(optional_holidays_path)
        expect(flash[:notice]).to eq(I18n.t('flash.optional_holidays.update.school_makeup_update_notice'))
      end

      it 'saves a different makeup date for each course of the school' do
        fundamental = create(:course, description: 'Fundamental')
        eja = create(:course, description: 'EJA')
        fundamental_classroom = create(:classroom, unity: unity, year: school_calendar.year, period: Periods::MATUTINAL)
        eja_classroom = create(:classroom, unity: unity, year: school_calendar.year, period: Periods::VESPERTINE)
        create(:classrooms_grade, classroom: fundamental_classroom, grade: create(:grade, course: fundamental))
        create(:classrooms_grade, classroom: eja_classroom, grade: create(:grade, course: eja))
        allow_any_instance_of(OptionalHolidayCalendarSynchronizer).to receive(:sync)
        general_date = holiday.holiday_date + 3.days
        fundamental_date = holiday.holiday_date + 4.days
        eja_date = holiday.holiday_date + 6.days

        patch :update, params: {
          locale: 'pt-BR',
          id: holiday.id,
          optional_holiday: {
            make_up_date: I18n.l(general_date),
            course_makeups: {
              fundamental.id.to_s => { course_id: fundamental.id, make_up_date: I18n.l(fundamental_date) },
              eja.id.to_s => { course_id: eja.id, make_up_date: I18n.l(eja_date) }
            }
          }
        }

        holiday.reload
        expect(response).to redirect_to(optional_holidays_path)
        expect(holiday.make_up_date_for(unity.id)).to eq(general_date)
        expect(holiday.make_up_date_for(unity.id, course_id: fundamental.id)).to eq(fundamental_date)
        expect(holiday.make_up_date_for(unity.id, course_id: eja.id)).to eq(eja_date)
        expect(
          OptionalHoliday.make_up_dates_for(
            classroom: fundamental_classroom,
            start_date: holiday.holiday_date,
            end_date: eja_date,
            period: Periods::MATUTINAL
          )
        ).to include(fundamental_date)
      end

      it 'drops a course makeup date left blank and falls back to the school date' do
        course = create(:course, description: 'Fundamental')
        course_classroom = create(:classroom, unity: unity, year: school_calendar.year, period: Periods::VESPERTINE)
        create(:classrooms_grade, classroom: course_classroom, grade: create(:grade, course: course))
        general_date = holiday.holiday_date + 3.days
        create(:optional_holiday_unity_makeup, optional_holiday: holiday, unity: unity, make_up_date: general_date)
        create(
          :optional_holiday_unity_makeup,
          optional_holiday: holiday,
          unity: unity,
          course: course,
          make_up_date: holiday.holiday_date + 5.days
        )
        allow_any_instance_of(OptionalHolidayCalendarSynchronizer).to receive(:sync)

        patch :update, params: {
          locale: 'pt-BR',
          id: holiday.id,
          optional_holiday: {
            make_up_date: I18n.l(general_date),
            course_makeups: {
              course.id.to_s => { course_id: course.id, make_up_date: '' }
            }
          }
        }

        expect(response).to redirect_to(optional_holidays_path)
        expect(OptionalHolidayUnityMakeup.where(optional_holiday: holiday, unity: unity, course_id: course.id)).to be_empty
        expect(holiday.reload.make_up_date_for(unity.id, course_id: course.id)).to eq(general_date)
      end

      it 'does not save a school makeup when the scope is municipal' do
        municipal = create(
          :optional_holiday,
          year: school_calendar.year,
          user: user,
          holiday_date: holiday.holiday_date + 1.day,
          makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL
        )

        patch :update, params: {
          locale: 'pt-BR',
          id: municipal.id,
          optional_holiday: {
            make_up_date: I18n.l(municipal.holiday_date + 3.days)
          }
        }

        expect(OptionalHolidayUnityMakeup.where(optional_holiday: municipal, unity: unity)).to be_empty
        expect(municipal.reload.make_up_date).to be_blank
        expect(response).to render_template(:edit)
      end

      it 'does not accept a blank makeup date' do
        patch :update, params: {
          locale: 'pt-BR',
          id: holiday.id,
          optional_holiday: {
            make_up_date: ''
          }
        }

        expect(OptionalHolidayUnityMakeup.where(optional_holiday: holiday, unity: unity)).to be_empty
        expect(response).to render_template(:edit)
      end
    end
  end
end
