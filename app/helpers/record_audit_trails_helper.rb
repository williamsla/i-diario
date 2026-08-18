# frozen_string_literal: true

module RecordAuditTrailsHelper
  def record_audit_trail_history_path(result)
    case result[:auditable_type]
    when 'DailyFrequency'
      history_daily_frequency_path(result[:auditable_id])
    when 'DisciplineContentRecord'
      history_discipline_content_record_path(result[:auditable_id])
    when 'KnowledgeAreaContentRecord'
      history_knowledge_area_content_record_path(result[:auditable_id])
    when 'Avaliation'
      history_avaliation_path(result[:auditable_id])
    when 'DailyNote'
      history_daily_note_path(result[:auditable_id])
    when 'DisciplineTeachingPlan'
      history_discipline_teaching_plan_path(result[:auditable_id])
    when 'KnowledgeAreaTeachingPlan'
      history_knowledge_area_teaching_plan_path(result[:auditable_id])
    when 'DisciplineLessonPlan'
      history_discipline_lesson_plan_path(result[:auditable_id])
    when 'KnowledgeAreaLessonPlan'
      history_knowledge_area_lesson_plan_path(result[:auditable_id])
    end
  end

  def record_audit_trail_show_history?(result)
    return true if result[:record_exists]

    result[:avaliation_id].present? && result[:auditable_type] != 'Avaliation'
  end

  def record_audit_trail_history_link(result)
    if result[:record_exists]
      record_audit_trail_history_path(result)
    elsif result[:avaliation_id].present?
      history_avaliation_path(result[:avaliation_id])
    end
  end

  def record_audit_trail_status_label(result)
    t("record_audit_trails.report.status.#{result[:status] || status_from_exists(result)}")
  end

  def record_audit_trail_status_badge_class(result)
    case result[:status]
    when 'active' then 'badge badge-success'
    when 'incomplete' then 'badge badge-warning'
    when 'removed' then 'badge badge-danger'
    else
      result[:record_exists] ? 'badge badge-success' : 'badge badge-danger'
    end
  end

  def record_audit_trail_calendar_badge_class(status)
    case status
    when 'recorded' then 'badge badge-success'
    when 'incomplete', 'mixed' then 'badge badge-warning'
    when 'deleted', 'missing' then 'badge badge-danger'
    else 'badge'
    end
  end

  def record_audit_trail_mismatch_reasons(result)
    Array(result[:mismatch_reasons]).map do |reason|
      t("services.record_audit_trail_phrase.reasons.#{reason}")
    end.join(', ')
  end

  def record_audit_trail_format_event_at(result)
    if result[:event_at].present?
      l(result[:event_at], format: :compressed)
    elsif result[:primary_at].present?
      l(result[:primary_at], format: :compressed)
    else
      '—'
    end
  end

  def record_audit_trail_format_pedagogical_date(result)
    date = result[:pedagogical_date] || result[:occurred_on]
    date.present? ? l(date.to_date) : '—'
  end

  private

  def status_from_exists(result)
    result[:record_exists] ? 'active' : 'removed'
  end
end
