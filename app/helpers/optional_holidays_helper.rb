# frozen_string_literal: true

module OptionalHolidaysHelper
  def optional_holiday_update_action_label(optional_holiday)
    return t('views.optional_holidays.edit.action') if administrator?

    key = if optional_holiday_school_makeup_informed?(optional_holiday)
            'views.optional_holidays.edit.school_makeup_update_action'
          else
            'views.optional_holidays.edit.school_makeup_action'
          end

    t(key)
  end

  def optional_holiday_school_makeup_title(optional_holiday)
    key = if optional_holiday_school_makeup_informed?(optional_holiday)
            'views.optional_holidays.edit.school_makeup_update_title'
          else
            'views.optional_holidays.edit.school_makeup_title'
          end

    t(key)
  end

  def optional_holiday_school_makeup_submit(optional_holiday)
    key = if optional_holiday_school_makeup_informed?(optional_holiday)
            'views.optional_holidays.edit.school_makeup_update_submit'
          else
            'views.optional_holidays.edit.school_makeup_submit'
          end

    t(key)
  end

  def optional_holiday_school_makeup_hint(optional_holiday)
    key = if optional_holiday_school_makeup_informed?(optional_holiday)
            'views.optional_holidays.edit.school_makeup_update_hint'
          else
            'views.optional_holidays.edit.school_makeup_hint'
          end

    t(key)
  end

  def optional_holiday_pending_makeup?(optional_holiday)
    if administrator?
      current_unity ? optional_holiday.pending_make_up_for?(current_unity.id) : optional_holiday.pending_make_up?
    else
      current_unity.present? && optional_holiday.school_can_inform_makeup?(current_unity.id)
    end
  end

  def optional_holiday_makeup?(classroom, date, period: nil)
    return false if classroom.blank? || date.blank?

    optional_holiday_makeup_dates_for(classroom, period: period).include?(date.to_date)
  end

  def optional_holiday_makeup_badge(classroom, date, period: nil)
    return unless optional_holiday_makeup?(classroom, date, period: period)

    optional_holiday_makeup_label_tag
  end

  def optional_holiday_makeup_badge_placeholder(classroom, date, period: nil, id: 'optional-holiday-makeup-badge')
    visible = optional_holiday_makeup?(classroom, date, period: period)

    optional_holiday_makeup_label_tag(
      id: id,
      style: visible ? nil : 'display:none;'
    )
  end

  private

  def optional_holiday_school_makeup_informed?(optional_holiday)
    return false if current_unity.blank?

    unity_id = current_unity.id.to_i
    optional_holiday.optional_holiday_unity_makeups.any? do |makeup|
      makeup.persisted? && makeup.unity_id == unity_id
    end
  end

  def optional_holiday_makeup_dates_for(classroom, period: nil)
    @optional_holiday_makeup_dates_for ||= {}
    key = [classroom.id, period.to_s]
    year = classroom.year.to_i

    @optional_holiday_makeup_dates_for[key] ||= OptionalHoliday.make_up_dates_for(
      classroom: classroom,
      start_date: Date.new(year, 1, 1),
      end_date: Date.new(year, 12, 31),
      period: period,
      unity_id: classroom.unity_id
    )
  end

  def optional_holiday_makeup_label_tag(id: nil, style: nil)
    content_tag(
      :span,
      "(#{OptionalHoliday.makeup_label})",
      class: 'optional-holiday-makeup-label',
      id: id,
      style: style
    )
  end
end
