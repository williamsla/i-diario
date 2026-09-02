# frozen_string_literal: true

class OptionalHolidaysController < ApplicationController
  has_scope :page, default: 1
  has_scope :per, default: 10
  has_scope :by_description, in: :filter

  before_action :require_current_unity, only: [:edit, :update]
  before_action :set_optional_holiday, only: [:show, :edit, :update, :destroy, :history]
  before_action :require_allow_to_modify_prev_years, only: [:create, :update, :destroy]

  def index
    @optional_holidays = fetch_optional_holidays
    authorize @optional_holidays
  end

  def show
    authorize @optional_holiday
    load_unity_makeup
  end

  def new
    @optional_holiday = OptionalHoliday.new(
      year: current_school_year,
      holiday_date: Date.current,
      periods: %w[1 2 3],
      makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL
    )
    authorize @optional_holiday
  end

  def create
    @optional_holiday = OptionalHoliday.new(resource_params)
    @optional_holiday.user = current_user
    @optional_holiday.year = current_school_year if @optional_holiday.year.blank?

    authorize @optional_holiday

    if @optional_holiday.save
      OptionalHolidayCalendarSynchronizer.new(@optional_holiday).sync
      flash[:notice] = I18n.t('flash.optional_holidays.create.notice')
      respond_with @optional_holiday, location: optional_holidays_path
    else
      render :new
    end
  end

  def edit
    authorize @optional_holiday
    load_unity_makeup
  end

  def update
    authorize @optional_holiday

    saved = if administrator?
              @optional_holiday.update(resource_params)
            else
              save_unity_makeup
            end

    if saved
      @optional_holiday.reload
      OptionalHolidayCalendarSynchronizer.new(@optional_holiday).sync
      flash[:notice] = I18n.t('flash.optional_holidays.update.notice')
      respond_with @optional_holiday, location: optional_holidays_path
    else
      load_unity_makeup
      render :edit
    end
  end

  def destroy
    authorize @optional_holiday
    OptionalHolidayCalendarSynchronizer.new(@optional_holiday).destroy_events
    @optional_holiday.destroy
    flash[:notice] = I18n.t('flash.optional_holidays.destroy.notice')
    respond_with @optional_holiday, location: optional_holidays_path
  end

  def history
    authorize @optional_holiday
    respond_with @optional_holiday
  end

  helper_method :administrator?

  private

  def resource_params
    permitted = params.require(:optional_holiday).permit(
      :holiday_date,
      :description,
      :makeup_scope,
      :make_up_date,
      :periods,
      periods: [],
      optional_holiday_attachments_attributes: [
        :id,
        :attachment,
        :_destroy
      ]
    )
    permitted[:year] = current_school_year
    permitted[:periods] = Array(permitted[:periods]).join(',').split(',').map(&:strip).reject(&:blank?)
    permitted
  end

  def unity_makeup_params
    params.require(:optional_holiday).permit(:make_up_date)
  end

  def set_optional_holiday
    @optional_holiday = OptionalHoliday.includes(
      :optional_holiday_attachments,
      optional_holiday_unity_makeups: :unity
    ).find(params[:id])
  end

  def fetch_optional_holidays
    apply_scopes(
      OptionalHoliday
        .includes(:optional_holiday_unity_makeups, :optional_holiday_attachments)
        .by_year(current_school_year)
        .ordered
    )
  end

  def load_unity_makeup
    return unless current_unity

    @unity_makeup = @optional_holiday.unity_makeup_for(current_unity.id)
    return if administrator? || @optional_holiday.makeup_scope_municipal?

    @optional_holiday.make_up_date = @unity_makeup.make_up_date
    @optional_holiday.equivalent_weekday = @unity_makeup.equivalent_weekday
  end

  def save_unity_makeup
    makeup = @optional_holiday.unity_makeup_for(current_unity.id)
    makeup.user = current_user
    makeup.assign_attributes(unity_makeup_params)

    if makeup.make_up_date.blank?
      makeup.destroy if makeup.persisted?
      return true
    end

    makeup.save
  end

  def administrator?
    current_user.current_user_role&.role&.access_level == AccessLevel::ADMINISTRATOR
  end
end
