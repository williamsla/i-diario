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
    end
  end
end
