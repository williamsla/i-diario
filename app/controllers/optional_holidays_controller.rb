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
  end

  def new
    @optional_holiday = OptionalHoliday.new(
      year: current_school_year,
      holiday_date: Date.current,
      periods: %w[1 2 3],
      makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL
    )
    authorize @optional_holiday
    load_course_makeup_fields
  end

  def create
    @optional_holiday = OptionalHoliday.new(resource_params)
    @optional_holiday.user = current_user
    @optional_holiday.year = current_school_year if @optional_holiday.year.blank?

    authorize @optional_holiday

    if save_administrator_holiday
      @optional_holiday.reload
      OptionalHolidayCalendarSynchronizer.new(@optional_holiday).sync
      flash[:notice] = I18n.t('flash.optional_holidays.create.notice')
      respond_with @optional_holiday, location: optional_holidays_path
    else
      load_course_makeup_fields
      render :new
    end
  end

  def edit
    authorize @optional_holiday
    load_unity_makeup
    load_course_makeup_fields
  end

  def update
    authorize @optional_holiday

    saved = if administrator?
              save_administrator_holiday
            else
              save_unity_makeup
            end

    if saved
      @optional_holiday.reload
      OptionalHolidayCalendarSynchronizer.new(@optional_holiday).sync
      flash[:notice] = update_notice
      respond_with @optional_holiday, location: optional_holidays_path
    else
      load_unity_makeup
      load_course_makeup_fields
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
      optional_holiday_course_makeups: :course,
      optional_holiday_unity_makeups: [:unity, :course]
    ).find(params[:id])
  end

  def fetch_optional_holidays
    apply_scopes(
      OptionalHoliday
        .includes(
          :optional_holiday_unity_makeups,
          :optional_holiday_course_makeups,
          :optional_holiday_attachments
        )
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

  def save_administrator_holiday
    prepare_course_makeup_fields
    was_new = @optional_holiday.new_record?
    saved = false

    OptionalHoliday.transaction do
      updated = was_new ? @optional_holiday.save : @optional_holiday.update(resource_params)
      raise ActiveRecord::Rollback unless updated
      raise ActiveRecord::Rollback unless persist_prepared_course_makeups!

      saved = true
    end

    restore_unsaved_holiday if was_new && !saved
    saved
  end

  def restore_unsaved_holiday
    @optional_holiday.instance_variable_set(:@new_record, true)
    @optional_holiday.id = nil
  end

  def save_unity_makeup
    unless @optional_holiday.makeup_scope_by_school?
      @optional_holiday.errors.add(:makeup_scope, :school_cannot_inform)
      return false
    end

    makeup = @optional_holiday.unity_makeup_for(current_unity.id)
    @updating_existing_makeup = makeup.persisted?
    makeup.user = current_user
    makeup.make_up_date = unity_makeup_params[:make_up_date]
    prepare_course_makeup_fields

    saved = false
    OptionalHoliday.transaction do
      if makeup.make_up_date.blank?
        add_makeup_error(makeup, :make_up_date, :blank)
        raise ActiveRecord::Rollback
      end

      unless makeup.save
        copy_makeup_errors(makeup)
        raise ActiveRecord::Rollback
      end

      raise ActiveRecord::Rollback unless persist_prepared_course_makeups!

      saved = true
    end

    saved
  end

  def load_course_makeup_fields
    return if @course_makeup_fields
    return if administrator? && @optional_holiday.makeup_scope_by_school?

    prepare_course_makeup_fields
  end

  def prepare_course_makeup_fields
    return if @course_makeup_fields

    unity_id = administrator? ? nil : current_unity&.id
    submitted = course_makeup_params
    courses = OptionalHoliday.courses_for_year(
      @optional_holiday.year.presence || current_school_year,
      unity_id: unity_id
    )

    @course_makeup_fields = courses.map do |course|
      makeup = find_or_build_course_makeup(unity_id, course)
      raw_date = nil
      if course_makeups_submitted?
        attrs = submitted[course.id.to_s] || {}
        raw_date = attrs[:make_up_date].to_s.strip
        makeup.make_up_date = raw_date.presence
      end
      { course: course, makeup: makeup, raw_date: raw_date }
    end
  end

  def find_or_build_course_makeup(unity_id, course)
    if unity_id
      @optional_holiday.optional_holiday_unity_makeups.detect { |makeup|
        makeup.unity_id == unity_id.to_i && makeup.course_id == course.id
      } || @optional_holiday.optional_holiday_unity_makeups.build(unity_id: unity_id, course: course)
    else
      @optional_holiday.optional_holiday_course_makeups.detect { |makeup|
        makeup.course_id == course.id
      } || @optional_holiday.optional_holiday_course_makeups.build(course: course)
    end
  end

  def persist_prepared_course_makeups!
    if administrator? && @optional_holiday.makeup_scope_by_school?
      @optional_holiday.optional_holiday_course_makeups.destroy_all
      return true
    end

    return true unless course_makeups_submitted?

    @course_makeup_fields.to_a.each do |field|
      makeup = field[:makeup]
      raw_date = field[:raw_date].to_s.strip
      if raw_date.blank?
        makeup.destroy if makeup.persisted?
        next
      end

      makeup.user = current_user
      makeup.optional_holiday = @optional_holiday
      makeup.make_up_date = raw_date
      next if makeup.save

      @optional_holiday.errors.add(
        :base,
        "#{field[:course].description}: #{makeup.errors.full_messages.to_sentence}"
      )
      return false
    end

    true
  end

  def course_makeups_submitted?
    params[:optional_holiday].present? && params[:optional_holiday].key?(:course_makeups)
  end

  def course_makeup_params
    permitted = params.fetch(:optional_holiday, ActionController::Parameters.new)
                      .permit(course_makeups: [:id, :course_id, :make_up_date])
    raw = permitted[:course_makeups]
    return {} if raw.blank?

    raw.to_h.each_with_object({}) do |(course_id, attrs), result|
      result[course_id.to_s] = attrs.symbolize_keys
    end
  end

  def add_makeup_error(makeup, attribute, error)
    makeup.errors.add(attribute, error)
    @optional_holiday.errors.add(attribute, makeup.errors[attribute].last)
  end

  def copy_makeup_errors(makeup)
    makeup.errors.each do |attribute, message|
      @optional_holiday.errors.add(attribute, message)
    end
  end

  def update_notice
    if administrator?
      I18n.t('flash.optional_holidays.update.notice')
    elsif @updating_existing_makeup
      I18n.t('flash.optional_holidays.update.school_makeup_update_notice')
    else
      I18n.t('flash.optional_holidays.update.school_makeup_notice')
    end
  end

  def administrator?
    current_user.current_user_role&.role&.access_level == AccessLevel::ADMINISTRATOR
  end
end
