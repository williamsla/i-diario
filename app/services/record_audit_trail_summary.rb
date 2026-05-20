# frozen_string_literal: true

class RecordAuditTrailSummary
  AUDITABLE_TYPES_BY_RECORD_TYPE = {
    'frequency' => ['DailyFrequency'],
    'content' => %w[DisciplineContentRecord KnowledgeAreaContentRecord],
    'avaliation' => ['Avaliation']
  }.freeze

  def initialize(unity_id:, classroom_id:, teacher_id:, discipline_id:, start_date:, end_date:, record_types:)
    @unity_id = unity_id
    @classroom_id = classroom_id
    @teacher_id = teacher_id
    @discipline_id = discipline_id
    @start_date = start_date.to_date
    @end_date = end_date.to_date
    @record_types = Array(record_types)
  end

  def call
    entries = collect_record_entries
    collected_keys = entries.map { |entry| entry_key(entry) }
    entries.concat(collect_destroyed_entries(collected_keys))
    entries = deduplicate_entries(entries)

    audit_groups = fetch_audit_groups(entries)
    build_results(entries, audit_groups)
  end

  private

  def collect_record_entries
    entries = []

    entries.concat(frequency_entries) if @record_types.include?('frequency')
    entries.concat(discipline_content_entries) if @record_types.include?('content')
    entries.concat(knowledge_area_content_entries) if @record_types.include?('content') && @discipline_id.blank?
    entries.concat(avaliation_entries) if @record_types.include?('avaliation')

    entries
  end

  def frequency_entries
    scope = DailyFrequency.where(unity_id: @unity_id)
                          .where(frequency_date: @start_date..@end_date)
    scope = scope.where(classroom_id: @classroom_id) if @classroom_id.present?
    scope = scope.by_owner_teacher_id(@teacher_id) if @teacher_id.present?
    scope = scope.where(discipline_id: @discipline_id) if @discipline_id.present?

    scope.includes(:classroom, :discipline, :teacher).map do |record|
      build_entry(
        auditable_type: 'DailyFrequency',
        auditable_id: record.id,
        record_type: 'frequency',
        record: record,
        occurred_on: record.frequency_date,
        label: frequency_label(record)
      )
    end
  end

  def discipline_content_entries
    scope = DisciplineContentRecord.by_unity_id(@unity_id)
                                   .joins(:content_record)
                                   .where(content_records: { record_date: @start_date..@end_date })
    scope = scope.by_classroom_id(@classroom_id) if @classroom_id.present?
    scope = scope.by_teacher_id(@teacher_id) if @teacher_id.present?
    scope = scope.where(discipline_id: @discipline_id) if @discipline_id.present?

    scope.includes(:discipline, content_record: :classroom).map do |record|
      build_entry(
        auditable_type: 'DisciplineContentRecord',
        auditable_id: record.id,
        record_type: 'content',
        record: record,
        occurred_on: record.content_record.record_date,
        label: discipline_content_label(record)
      )
    end
  end

  def knowledge_area_content_entries
    scope = KnowledgeAreaContentRecord.by_unity_id(@unity_id)
                                      .joins(:content_record)
                                      .where(content_records: { record_date: @start_date..@end_date })
    scope = scope.by_classroom_id(@classroom_id) if @classroom_id.present?
    scope = scope.by_teacher_id(@teacher_id) if @teacher_id.present?

    scope.includes(content_record: :classroom, knowledge_areas: []).map do |record|
      build_entry(
        auditable_type: 'KnowledgeAreaContentRecord',
        auditable_id: record.id,
        record_type: 'content',
        record: record,
        occurred_on: record.content_record.record_date,
        label: knowledge_area_content_label(record)
      )
    end
  end

  def avaliation_entries
    scope = Avaliation.by_unity_id(@unity_id)
                      .by_test_date_between(@start_date, @end_date)
    scope = scope.by_classroom_id(@classroom_id) if @classroom_id.present?
    scope = scope.by_teacher(@teacher_id) if @teacher_id.present?
    scope = scope.by_discipline_id(@discipline_id) if @discipline_id.present?

    scope.includes(:classroom, :discipline).map do |record|
      build_entry(
        auditable_type: 'Avaliation',
        auditable_id: record.id,
        record_type: 'avaliation',
        record: record,
        occurred_on: record.test_date,
        label: avaliation_label(record)
      )
    end
  end

  def collect_destroyed_entries(collected_keys)
    auditable_types = @record_types.flat_map { |type| AUDITABLE_TYPES_BY_RECORD_TYPE[type] }.uniq
    return [] if auditable_types.blank?

    period = @start_date.beginning_of_day..@end_date.end_of_day

    Audited::Audit.where(auditable_type: auditable_types, action: 'destroy', created_at: period)
                  .includes(:user)
                  .reject { |audit| collected_keys.include?([audit.auditable_type, audit.auditable_id]) }
                  .select { |audit| matches_destroyed_audit?(audit) }
                  .map { |audit| build_destroyed_entry(audit) }
                  .compact
  end

  def matches_destroyed_audit?(audit)
    changes = audited_changes_hash(audit)

    case audit.auditable_type
    when 'DailyFrequency'
      matches_frequency_changes?(changes)
    when 'DisciplineContentRecord'
      matches_discipline_content_changes?(changes, audit)
    when 'KnowledgeAreaContentRecord'
      matches_knowledge_area_content_changes?(changes, audit)
    when 'Avaliation'
      matches_avaliation_changes?(changes)
    else
      false
    end
  end

  def matches_frequency_changes?(changes)
    return false unless unity_matches?(changes['unity_id'])
    return false if @classroom_id.present? && changes['classroom_id'].to_i != @classroom_id.to_i
    return false if @teacher_id.present? && changes['owner_teacher_id'].to_i != @teacher_id.to_i
    return false if @discipline_id.present? && changes['discipline_id'].to_i != @discipline_id.to_i

    frequency_date_in_range?(changes['frequency_date'])
  end

  def matches_discipline_content_changes?(changes, audit)
    content_attrs = content_record_attrs_from_audit(audit, changes)
    return false if content_attrs.blank?

    classroom = Classroom.find_by(id: content_attrs['classroom_id'])
    return false unless unity_matches?(classroom&.unity_id)
    return false if @classroom_id.present? && content_attrs['classroom_id'].to_i != @classroom_id.to_i
    return false if @teacher_id.present? && content_attrs['teacher_id'].to_i != @teacher_id.to_i
    return false if @discipline_id.present? && changes['discipline_id'].to_i != @discipline_id.to_i

    record_date_in_range?(content_attrs['record_date'])
  end

  def matches_knowledge_area_content_changes?(changes, audit)
    content_attrs = content_record_attrs_from_audit(audit, changes)
    return false if content_attrs.blank?
    return false unless unity_matches?(Classroom.find_by(id: content_attrs['classroom_id'])&.unity_id)
    return false if @classroom_id.present? && content_attrs['classroom_id'].to_i != @classroom_id.to_i
    return false if @teacher_id.present? && content_attrs['teacher_id'].to_i != @teacher_id.to_i

    record_date_in_range?(content_attrs['record_date'])
  end

  def matches_avaliation_changes?(changes)
    classroom = Classroom.find_by(id: changes['classroom_id'])
    return false unless unity_matches?(classroom&.unity_id)
    return false if @classroom_id.present? && changes['classroom_id'].to_i != @classroom_id.to_i
    return false if @discipline_id.present? && changes['discipline_id'].to_i != @discipline_id.to_i
    return false if @teacher_id.present? && !teacher_linked_to_avaliation?(changes)

    test_date_in_range?(changes['test_date'])
  end

  def teacher_linked_to_avaliation?(changes)
    Avaliation.by_teacher(@teacher_id)
              .where(id: changes['id'])
              .exists? ||
      TeacherDisciplineClassroom.exists?(
        teacher_id: @teacher_id,
        classroom_id: changes['classroom_id'],
        discipline_id: changes['discipline_id']
      )
  end

  def build_destroyed_entry(audit)
    changes = audited_changes_hash(audit)
    label = destroyed_label(audit, changes)
    occurred_on = occurred_on_from_destroyed(audit, changes)

    build_entry(
      auditable_type: audit.auditable_type,
      auditable_id: audit.auditable_id,
      record_type: record_type_for(audit.auditable_type),
      record: nil,
      occurred_on: occurred_on,
      label: label
    )
  end

  def build_entry(auditable_type:, auditable_id:, record_type:, record:, occurred_on:, label:)
    {
      auditable_type: auditable_type,
      auditable_id: auditable_id,
      record_type: record_type,
      record: record,
      occurred_on: occurred_on,
      label: label
    }
  end

  def deduplicate_entries(entries)
    entries.uniq { |entry| entry_key(entry) }
  end

  def entry_key(entry)
    [entry[:auditable_type], entry[:auditable_id]]
  end

  def fetch_audit_groups(entries)
    return {} if entries.blank?

    auditable_types = entries.map { |entry| entry[:auditable_type] }.uniq
    auditable_ids = entries.map { |entry| entry[:auditable_id] }

    audits = Audited::Audit.where(auditable_type: auditable_types, auditable_id: auditable_ids)
                           .includes(:user)
                           .order(:created_at)

    audits.group_by { |audit| [audit.auditable_type, audit.auditable_id] }
  end

  def build_results(entries, audit_groups)
    entries.map do |entry|
      audits = audit_groups[entry_key(entry)] || []
      events = build_events(audits)
      record_exists = entry[:record].present?

      {
        auditable_type: entry[:auditable_type],
        auditable_id: entry[:auditable_id],
        record_type: entry[:record_type],
        record_type_label: record_type_label(entry[:record_type]),
        occurred_on: entry[:occurred_on],
        label: entry[:label],
        record_exists: record_exists,
        events: events,
        summary: build_summary(events),
        verdict: build_verdict(events, record_exists)
      }
    end.sort_by { |result| [result[:occurred_on], result[:label]] }.reverse
  end

  def build_events(audits)
    audits.map do |audit|
      {
        action: audit.action,
        action_label: AuditedAction.t(audit.action),
        at: audit.created_at,
        user_name: audit.user&.to_s || I18n.t('services.record_audit_trail_summary.system_user')
      }
    end
  end

  def build_summary(events)
    return I18n.t('services.record_audit_trail_summary.no_events') if events.blank?

    events.map do |event|
      I18n.t(
        'services.record_audit_trail_summary.event_line',
        action: event[:action_label],
        datetime: I18n.l(event[:at], format: :compressed),
        user: event[:user_name]
      )
    end.join('; ')
  end

  def build_verdict(events, record_exists)
    create_event = events.find { |event| event[:action] == 'create' }
    destroy_event = events.find { |event| event[:action] == 'destroy' }
    update_events = events.select { |event| event[:action] == 'update' }

    if events.blank?
      return I18n.t('services.record_audit_trail_summary.verdict.no_audit_trail') if record_exists

      return I18n.t('services.record_audit_trail_summary.verdict.never_persisted')
    end

    if create_event.blank? && destroy_event.present?
      return I18n.t(
        'services.record_audit_trail_summary.verdict.destroyed_without_create',
        datetime: I18n.l(destroy_event[:at], format: :compressed),
        user: destroy_event[:user_name]
      )
    end

    if destroy_event.present?
      return I18n.t(
        'services.record_audit_trail_summary.verdict.destroyed',
        datetime: I18n.l(destroy_event[:at], format: :compressed),
        user: destroy_event[:user_name]
      )
    end

    if create_event.present? && record_exists
      last_change = update_events.last || create_event
      return I18n.t(
        'services.record_audit_trail_summary.verdict.active',
        datetime: I18n.l(last_change[:at], format: :compressed),
        user: last_change[:user_name]
      )
    end

    if create_event.present?
      return I18n.t(
        'services.record_audit_trail_summary.verdict.created',
        datetime: I18n.l(create_event[:at], format: :compressed),
        user: create_event[:user_name]
      )
    end

    I18n.t('services.record_audit_trail_summary.verdict.unknown')
  end

  def frequency_label(record)
    discipline = record.discipline&.to_s || I18n.t('services.record_audit_trail_summary.general_frequency')
    "#{discipline} — #{record.classroom} — #{I18n.l(record.frequency_date)}"
  end

  def discipline_content_label(record)
    "#{record.discipline} — #{record.classroom} — #{I18n.l(record.content_record.record_date)}"
  end

  def knowledge_area_content_label(record)
    areas = record.knowledge_areas.map(&:to_s).join(', ')
    "#{areas} — #{record.classroom} — #{I18n.l(record.content_record.record_date)}"
  end

  def avaliation_label(record)
    "#{record} — #{record.discipline} — #{I18n.l(record.test_date)}"
  end

  def destroyed_label(audit, changes)
    case audit.auditable_type
    when 'DailyFrequency'
      discipline_name = Discipline.find_by(id: changes['discipline_id'])&.to_s ||
                        I18n.t('services.record_audit_trail_summary.general_frequency')
      classroom_name = Classroom.find_by(id: changes['classroom_id'])&.to_s || '-'
      date = parse_date(changes['frequency_date'])
      "#{discipline_name} — #{classroom_name} — #{I18n.l(date)} (#{I18n.t('services.record_audit_trail_summary.removed')})"
    when 'DisciplineContentRecord'
      discipline_name = Discipline.find_by(id: changes['discipline_id'])&.to_s || '-'
      content_attrs = changes['content_record'] || {}
      classroom_name = Classroom.find_by(id: content_attrs['classroom_id'])&.to_s || '-'
      date = parse_date(content_attrs['record_date'])
      "#{discipline_name} — #{classroom_name} — #{I18n.l(date)} (#{I18n.t('services.record_audit_trail_summary.removed')})"
    when 'KnowledgeAreaContentRecord'
      content_attrs = changes['content_record'] || {}
      classroom_name = Classroom.find_by(id: content_attrs['classroom_id'])&.to_s || '-'
      date = parse_date(content_attrs['record_date'])
      "#{classroom_name} — #{I18n.l(date)} (#{I18n.t('services.record_audit_trail_summary.removed')})"
    when 'Avaliation'
      discipline_name = Discipline.find_by(id: changes['discipline_id'])&.to_s || '-'
      date = parse_date(changes['test_date'])
      description = changes['description'].presence || '-'
      "#{description} — #{discipline_name} — #{I18n.l(date)} (#{I18n.t('services.record_audit_trail_summary.removed')})"
    else
      I18n.t('services.record_audit_trail_summary.removed_record')
    end
  end

  def occurred_on_from_destroyed(audit, changes)
    case audit.auditable_type
    when 'DailyFrequency' then parse_date(changes['frequency_date'])
    when 'Avaliation' then parse_date(changes['test_date'])
    when 'DisciplineContentRecord', 'KnowledgeAreaContentRecord'
      content_attrs = changes['content_record'] || content_record_attrs_from_audit(audit, changes)
      parse_date(content_attrs['record_date'])
    else
      audit.created_at.to_date
    end
  end

  def content_record_attrs_from_audit(audit, changes)
    nested = changes['content_record']
    return nested if nested.is_a?(Hash) && nested['classroom_id'].present?

    content_record_id = changes['content_record_id'] || nested&.dig('id')
    return {} if content_record_id.blank?

    content_audit = Audited::Audit.where(auditable_type: 'ContentRecord', auditable_id: content_record_id)
                                  .order(:created_at)
                                  .first

    audited_changes_hash(content_audit) if content_audit
  end

  def audited_changes_hash(audit)
    changes = audit.audited_changes
    return changes if changes.is_a?(Hash)

    parse_audited_changes_yaml(changes) || {}
  rescue StandardError
    {}
  end

  def parse_audited_changes_yaml(yaml)
    YAML.safe_load(
      yaml,
      [Date, Time, ActiveSupport::TimeWithZone, BigDecimal, Symbol],
      [],
      true
    )
  end

  def unity_matches?(unity_id)
    return true if @unity_id.blank?

    unity_id.to_i == @unity_id.to_i
  end

  def frequency_date_in_range?(value)
    date = parse_date(value)
    date.present? && date.between?(@start_date, @end_date)
  end

  def record_date_in_range?(value)
    frequency_date_in_range?(value)
  end

  def test_date_in_range?(value)
    frequency_date_in_range?(value)
  end

  def parse_date(value)
    return value.to_date if value.is_a?(Date) || value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def record_type_for(auditable_type)
    AUDITABLE_TYPES_BY_RECORD_TYPE.find { |_type, types| types.include?(auditable_type) }&.first || 'unknown'
  end

  def record_type_label(record_type)
    I18n.t("services.record_audit_trail_summary.record_types.#{record_type}", default: record_type)
  end
end
