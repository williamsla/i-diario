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
end
