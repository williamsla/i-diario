# frozen_string_literal: true

module SchoolCalendarPostingDatesHelper
  def posting_dates_current_value(dates)
    unique = Array(dates).compact.uniq.sort
    return '—' if unique.empty?
    return l(unique.first) if unique.size == 1

    t('school_calendar_posting_dates.edit.mixed_dates')
  end

  def posting_dates_current_title(dates)
    unique = Array(dates).compact.uniq.sort
    return if unique.size <= 1

    unique.map { |date| l(date) }.join(', ')
  end

  def posting_dates_reach_parts(group)
    parts = []
    if group.school_count.positive?
      parts << t('school_calendar_posting_dates.edit.schools_count', count: group.school_count)
    end
    if group.classroom_step_count.positive?
      parts << t('school_calendar_posting_dates.edit.classroom_steps_count', count: group.classroom_step_count)
    end
    parts
  end
end
