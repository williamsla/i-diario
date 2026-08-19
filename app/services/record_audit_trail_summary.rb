# frozen_string_literal: true

class RecordAuditTrailSummary
  AUDITABLE_TYPES_BY_RECORD_TYPE = {
    'frequency' => ['DailyFrequency'],
    'content' => %w[DisciplineContentRecord KnowledgeAreaContentRecord],
    'avaliation' => ['Avaliation'],
    'grades' => %w[DailyNote DailyNoteStudent],
    'teaching_plan' => %w[DisciplineTeachingPlan KnowledgeAreaTeachingPlan],
    'lesson_plan' => %w[DisciplineLessonPlan KnowledgeAreaLessonPlan],
    'opinion' => %w[DescriptiveExam ConceptualExam]
  }.freeze

  GRADE_NOTE_BATCH_TYPE = 'GradeNoteBatch'
  CONCEPTUAL_EXAM_BATCH_TYPE = 'ConceptualExamBatch'

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
    collected_keys = entries.map { |entry| entry_key(entry) }
    entries.concat(collect_grade_note_batch_entries(collected_keys))
    collected_keys = entries.map { |entry| entry_key(entry) }
    entries.concat(collect_avaliation_audit_entries(collected_keys))
    entries = deduplicate_entries(entries)

    audit_groups = fetch_audit_groups(entries)
    build_results(entries, audit_groups)
  end

  private

  def collect_record_entries
    entries = []

    entries.concat(frequency_entries) if @record_types.include?('frequency')
    entries.concat(discipline_content_entries) if @record_types.include?('content')
    entries.concat(knowledge_area_content_entries) if @record_types.include?('content')
    entries.concat(avaliation_entries) if @record_types.include?('avaliation')
    entries.concat(daily_note_entries) if @record_types.include?('grades')
    entries.concat(discipline_teaching_plan_entries) if @record_types.include?('teaching_plan')
    entries.concat(knowledge_area_teaching_plan_entries) if @record_types.include?('teaching_plan')
    entries.concat(discipline_lesson_plan_entries) if @record_types.include?('lesson_plan')
    entries.concat(knowledge_area_lesson_plan_entries) if @record_types.include?('lesson_plan')
    entries.concat(descriptive_exam_entries) if @record_types.include?('opinion')
    entries.concat(conceptual_exam_batch_entries) if @record_types.include?('opinion')

    entries
  end

  def frequency_entries
    scope = DailyFrequency.where(unity_id: @unity_id)
                          .where(frequency_date: @start_date..@end_date)
    scope = scope.where(classroom_id: @classroom_id) if @classroom_id.present?
    scope = scope.by_owner_teacher_id(@teacher_id) if @teacher_id.present?
    scope = apply_frequency_discipline_filter(scope)

    scope.includes(:classroom, :discipline, :teacher, :students).map do |record|
      build_entry(
        auditable_type: 'DailyFrequency',
        auditable_id: record.id,
        record_type: 'frequency',
        record: record,
        occurred_on: record.frequency_date,
        label: frequency_label(record),
        **frequency_context(record)
      )
    end
  end

  def discipline_content_entries
    scope = DisciplineContentRecord.by_unity_id(@unity_id)
                                   .joins(:content_record)
                                   .where(content_records: { record_date: @start_date..@end_date })
    scope = scope.by_classroom_id(@classroom_id) if @classroom_id.present?
    scope = scope.by_teacher_id(@teacher_id) if @teacher_id.present?
    scope = apply_discipline_filter(scope)

    scope.includes(:discipline, content_record: %i[classroom teacher]).map do |record|
      build_entry(
        auditable_type: 'DisciplineContentRecord',
        auditable_id: record.id,
        record_type: 'content',
        record: record,
        occurred_on: record.content_record.record_date,
        label: discipline_content_label(record),
        **discipline_content_context(record)
      )
    end
  end

  def knowledge_area_content_entries
    scope = KnowledgeAreaContentRecord.by_unity_id(@unity_id)
                                      .joins(:content_record)
                                      .where(content_records: { record_date: @start_date..@end_date })
    scope = scope.by_classroom_id(@classroom_id) if @classroom_id.present?
    scope = scope.by_teacher_id(@teacher_id) if @teacher_id.present?
    scope = apply_knowledge_area_filter(scope)

    scope.includes(content_record: %i[classroom teacher], knowledge_areas: []).map do |record|
      build_entry(
        auditable_type: 'KnowledgeAreaContentRecord',
        auditable_id: record.id,
        record_type: 'content',
        record: record,
        occurred_on: record.content_record.record_date,
        label: knowledge_area_content_label(record),
        **knowledge_area_content_context(record)
      )
    end
  end

  def avaliation_entries
    scope = Avaliation.by_unity_id(@unity_id)
                      .by_test_date_between(@start_date, @end_date)
    scope = scope.by_classroom_id(@classroom_id) if @classroom_id.present?
    scope = scope.by_teacher(@teacher_id) if @teacher_id.present?
    scope = apply_discipline_filter(scope)

    scope.includes(:classroom, :discipline).map do |record|
      build_entry(
        auditable_type: 'Avaliation',
        auditable_id: record.id,
        record_type: 'avaliation',
        record: record,
        occurred_on: record.test_date,
        label: avaliation_label(record),
        avaliation_id: record.id
      )
    end
  end

  def daily_note_entries
    scope = daily_notes_filtered_scope

    scope.preload(avaliation: %i[classroom discipline]).map do |record|
      avaliation = record.avaliation

      build_entry(
        auditable_type: 'DailyNote',
        auditable_id: record.id,
        record_type: 'grades',
        record: record,
        occurred_on: avaliation.test_date,
        label: daily_note_active_label(avaliation),
        avaliation_id: avaliation.id
      )
    end
  end

  def discipline_teaching_plan_entries
    scope = DisciplineTeachingPlan.by_unity(@unity_id)
                                  .joins(:teaching_plan)
                                  .where(teaching_plans: { year: @start_date.year..@end_date.year })
                                  .where(
                                    'DATE(teaching_plans.created_at) BETWEEN :start_date AND :end_date OR ' \
                                    'DATE(teaching_plans.updated_at) BETWEEN :start_date AND :end_date',
                                    start_date: @start_date,
                                    end_date: @end_date
                                  )
    scope = scope.by_teacher_id(@teacher_id) if @teacher_id.present?
    scope = apply_discipline_filter(scope)
    scope = scope.by_grade(classroom_grade_ids) if @classroom_id.present?

    scope.includes(:discipline, teaching_plan: %i[grade school_term_type school_term_type_step]).map do |record|
      build_entry(
        auditable_type: 'DisciplineTeachingPlan',
        auditable_id: record.id,
        record_type: 'teaching_plan',
        record: record,
        occurred_on: teaching_plan_occurred_on(record.teaching_plan),
        label: discipline_teaching_plan_label(record)
      )
    end
  end

  def knowledge_area_teaching_plan_entries
    scope = KnowledgeAreaTeachingPlan.by_unity(@unity_id)
                                     .joins(:teaching_plan)
                                     .where(teaching_plans: { year: @start_date.year..@end_date.year })
                                     .where(
                                       'DATE(teaching_plans.created_at) BETWEEN :start_date AND :end_date OR ' \
                                       'DATE(teaching_plans.updated_at) BETWEEN :start_date AND :end_date',
                                       start_date: @start_date,
                                       end_date: @end_date
                                     )
    scope = scope.by_teacher_id(@teacher_id) if @teacher_id.present?
    scope = scope.by_grade(classroom_grade_ids) if @classroom_id.present?
    scope = apply_knowledge_area_filter(scope, :by_knowledge_area)

    scope.includes(:knowledge_areas, teaching_plan: %i[grade school_term_type school_term_type_step]).map do |record|
      build_entry(
        auditable_type: 'KnowledgeAreaTeachingPlan',
        auditable_id: record.id,
        record_type: 'teaching_plan',
        record: record,
        occurred_on: teaching_plan_occurred_on(record.teaching_plan),
        label: knowledge_area_teaching_plan_label(record)
      )
    end
  end

  def discipline_lesson_plan_entries
    scope = DisciplineLessonPlan.by_unity_id(@unity_id)
                                .by_date_range(@start_date, @end_date)
    scope = scope.by_classroom_id(@classroom_id) if @classroom_id.present?
    scope = scope.by_teacher_id(@teacher_id) if @teacher_id.present?
    scope = apply_discipline_filter(scope)

    scope.includes(:discipline, lesson_plan: :classroom).map do |record|
      build_entry(
        auditable_type: 'DisciplineLessonPlan',
        auditable_id: record.id,
        record_type: 'lesson_plan',
        record: record,
        occurred_on: record.lesson_plan.start_at.to_date,
        label: discipline_lesson_plan_label(record)
      )
    end
  end

  def knowledge_area_lesson_plan_entries
    scope = KnowledgeAreaLessonPlan.joins(:lesson_plan)
                                   .merge(LessonPlan.by_unity_id(@unity_id))
                                   .by_date_range(@start_date, @end_date)
    scope = scope.by_classroom_id(@classroom_id) if @classroom_id.present?
    scope = scope.by_teacher_id(@teacher_id) if @teacher_id.present?
    scope = apply_knowledge_area_filter(scope)

    scope.includes(:knowledge_areas, lesson_plan: :classroom).map do |record|
      build_entry(
        auditable_type: 'KnowledgeAreaLessonPlan',
        auditable_id: record.id,
        record_type: 'lesson_plan',
        record: record,
        occurred_on: record.lesson_plan.start_at.to_date,
        label: knowledge_area_lesson_plan_label(record)
      )
    end
  end

  def descriptive_exam_entries
    scope = DescriptiveExam.joins(:classroom).where(classrooms: { unity_id: @unity_id })
    scope = scope.where(recorded_at: @start_date..@end_date)
    scope = scope.by_classroom_id(@classroom_id) if @classroom_id.present?
    scope = apply_descriptive_discipline_filter(scope)
    scope = scope.includes(:classroom, :discipline, :students)

    scope.select { |record| opinion_teacher_matches_classroom?(record.classroom_id) }.map do |record|
      build_entry(
        auditable_type: 'DescriptiveExam',
        auditable_id: record.id,
        record_type: 'opinion',
        record: descriptive_exam_persisted?(record) ? record : nil,
        occurred_on: record.recorded_at,
        label: descriptive_exam_label(record),
        **descriptive_exam_context(record)
      )
    end
  end

  def conceptual_exam_batch_entries
    scope = conceptual_exam_base_scope
    scope = apply_conceptual_discipline_filter(scope)
    exams = scope.includes(:classroom, :student, :conceptual_exam_values).select do |exam|
      opinion_teacher_matches_classroom?(exam.classroom_id)
    end

    exams.group_by { |exam| [exam.classroom_id, exam.step_number] }.map do |(classroom_id, step_number), group|
      kept_exams = group.select { |exam| exam.discarded_at.blank? }
      audits = Audited::Audit.where(auditable_type: 'ConceptualExam', auditable_id: group.map(&:id))
                             .includes(:user)
                             .order(:created_at)

      completeness = conceptual_exam_completeness(kept_exams.presence || group)
      sample = kept_exams.first || group.first

      build_entry(
        auditable_type: CONCEPTUAL_EXAM_BATCH_TYPE,
        auditable_id: "#{classroom_id}-#{step_number}",
        entry_key_override: [CONCEPTUAL_EXAM_BATCH_TYPE, "#{classroom_id}-#{step_number}"],
        record_type: 'opinion',
        record: kept_exams.first,
        occurred_on: group.map(&:recorded_at).compact.max,
        label: conceptual_exam_batch_label(sample, completeness),
        classroom_id: classroom_id,
        classroom_name: sample.classroom&.to_s,
        completeness: completeness,
        detail: opinion_completeness_detail(completeness),
        inline_audits: audits,
        history_id: kept_exams.first&.id
      )
    end
  end

  def collect_grade_note_batch_entries(collected_keys)
    return [] unless @record_types.include?('grades')

    period = @start_date.beginning_of_day..@end_date.end_of_day

    audits = Audited::Audit.where(auditable_type: 'DailyNoteStudent', action: 'update', created_at: period)
                           .includes(:user)
                           .select { |audit| note_audited_change?(audit) }
                           .select { |audit| teacher_audit_matches?(audit) }
                           .uniq { |audit| [audit.auditable_id, audit.created_at.change(usec: 0), audit.user_id] }

    grouped = audits.group_by { |audit| grade_batch_group_key(audit) }

    grouped.map do |group_key, group_audits|
      next if collected_keys.include?([GRADE_NOTE_BATCH_TYPE, group_key])

      context = daily_note_context(daily_note_id_from_audit(group_audits.first))
      next unless context
      next unless matches_daily_note_context?(context)

      stats = grade_batch_stats(group_audits)
      label = grade_batch_label(context, stats)
      occurred_on = group_audits.first.created_at.to_date

      build_entry(
        auditable_type: GRADE_NOTE_BATCH_TYPE,
        auditable_id: group_key,
        entry_key_override: [GRADE_NOTE_BATCH_TYPE, group_key],
        record_type: 'grades',
        record: DailyNote.find_by(id: context[:daily_note_id]),
        occurred_on: occurred_on,
        label: label,
        avaliation_id: context[:avaliation]&.id,
        inline_audits: group_audits,
        grade_batch_stats: stats
      )
    end.compact
  end

  def collect_avaliation_audit_entries(collected_keys)
    return [] unless @record_types.include?('avaliation')

    period = @start_date.beginning_of_day..@end_date.end_of_day

    Audited::Audit.where(auditable_type: 'Avaliation', action: 'create', created_at: period)
                  .includes(:user)
                  .select { |audit| teacher_audit_matches?(audit) }
                  .select { |audit| matches_avaliation_audit_context?(audited_changes_hash(audit)) }
                  .reject { |audit| collected_keys.include?([audit.auditable_type, audit.auditable_id]) }
                  .map do |audit|
                    changes = audited_changes_hash(audit)
                    test_date = parse_date(changes['test_date'])

                    build_entry(
                      auditable_type: 'Avaliation',
                      auditable_id: audit.auditable_id,
                      record_type: 'avaliation',
                      record: Avaliation.find_by(id: audit.auditable_id),
                      occurred_on: test_date || audit.created_at.to_date,
                      label: avaliation_label_from_changes(changes),
                      avaliation_id: audit.auditable_id,
                      inline_audits: [audit]
                    )
                  end
  end

  def collect_destroyed_entries(collected_keys)
    auditable_types = @record_types.flat_map { |type| AUDITABLE_TYPES_BY_RECORD_TYPE[type] }.uniq
    return [] if auditable_types.blank?

    period = destroy_audit_search_period

    Audited::Audit.where(auditable_type: auditable_types, action: 'destroy', created_at: period)
                  .includes(:user)
                  .reject { |audit| collected_keys.include?([audit.auditable_type, audit.auditable_id]) }
                  .select { |audit| teacher_audit_matches?(audit) }
                  .select { |audit| matches_destroyed_audit?(audit) }
                  .map { |audit| build_destroyed_entry(audit) }
                  .compact
  end

  def matches_destroyed_audit?(audit)
    changes = audited_changes_hash(audit)

    case audit.auditable_type
    when 'DailyFrequency'
      matches_frequency_changes?(changes, audit)
    when 'DisciplineContentRecord'
      matches_discipline_content_changes?(changes, audit)
    when 'KnowledgeAreaContentRecord'
      matches_knowledge_area_content_changes?(changes, audit)
    when 'Avaliation'
      matches_avaliation_destroy_changes?(changes)
    when 'DailyNote'
      matches_daily_note_changes?(changes)
    when 'DisciplineTeachingPlan'
      matches_discipline_teaching_plan_changes?(changes, audit)
    when 'KnowledgeAreaTeachingPlan'
      matches_knowledge_area_teaching_plan_changes?(changes, audit)
    when 'DisciplineLessonPlan'
      matches_discipline_lesson_plan_changes?(changes, audit)
    when 'KnowledgeAreaLessonPlan'
      matches_knowledge_area_lesson_plan_changes?(changes, audit)
    when 'DescriptiveExam'
      matches_descriptive_exam_changes?(changes, audit)
    when 'ConceptualExam'
      matches_conceptual_exam_changes?(changes, audit)
    else
      false
    end
  end

  def matches_frequency_changes?(changes, audit = nil)
    return false unless unity_matches?(changes['unity_id'])
    return false if @classroom_id.present? && changes['classroom_id'].to_i != @classroom_id.to_i
    return false if @teacher_id.present? && changes['owner_teacher_id'].to_i != @teacher_id.to_i
    return false unless discipline_id_matches_filter?(changes['discipline_id'], allow_blank: true)

    date_matches_filter?(changes['frequency_date'], audit)
  end

  def matches_discipline_content_changes?(changes, audit)
    content_attrs = content_record_attrs_from_audit(audit, changes)
    return false if content_attrs.blank?

    classroom = Classroom.find_by(id: content_attrs['classroom_id'])
    return false unless unity_matches?(classroom&.unity_id)
    return false if @classroom_id.present? && content_attrs['classroom_id'].to_i != @classroom_id.to_i
    return false if @teacher_id.present? && content_attrs['teacher_id'].to_i != @teacher_id.to_i
    return false unless discipline_id_matches_filter?(changes['discipline_id'])

    date_matches_filter?(content_attrs['record_date'], audit)
  end

  def matches_knowledge_area_content_changes?(changes, audit)
    content_attrs = content_record_attrs_from_audit(audit, changes)
    return false if content_attrs.blank?
    return false unless unity_matches?(Classroom.find_by(id: content_attrs['classroom_id'])&.unity_id)
    return false if @classroom_id.present? && content_attrs['classroom_id'].to_i != @classroom_id.to_i
    return false if @teacher_id.present? && content_attrs['teacher_id'].to_i != @teacher_id.to_i
    return false unless knowledge_area_ids_match_filter?(knowledge_area_ids_from_content_audit(audit, changes))

    date_matches_filter?(content_attrs['record_date'], audit)
  end

  def matches_avaliation_changes?(changes)
    return false unless matches_avaliation_audit_context?(changes)

    test_date_in_range?(changes['test_date'])
  end

  def matches_avaliation_audit_context?(changes)
    classroom = Classroom.find_by(id: changes['classroom_id'])
    return false unless unity_matches?(classroom&.unity_id)
    return false if @classroom_id.present? && changes['classroom_id'].to_i != @classroom_id.to_i
    return false unless discipline_id_matches_filter?(changes['discipline_id'])
    return false if @teacher_id.present? && !teacher_linked_to_avaliation?(changes)

    true
  end

  def matches_avaliation_destroy_changes?(changes)
    classroom = Classroom.find_by(id: changes['classroom_id'])
    return false unless unity_matches?(classroom&.unity_id)
    return false if @classroom_id.present? && changes['classroom_id'].to_i != @classroom_id.to_i
    return false unless discipline_id_matches_filter?(changes['discipline_id'])
    return false if @teacher_id.present? && !teacher_linked_to_avaliation?(changes)

    true
  end

  def matches_daily_note_changes?(changes)
    return false unless unity_matches?(changes['unity_id'])
    return false if @classroom_id.present? && changes['classroom_id'].to_i != @classroom_id.to_i
    return false unless discipline_id_matches_filter?(changes['discipline_id'])

    true
  end

  def matches_discipline_teaching_plan_changes?(changes, audit)
    teaching_plan_attrs = teaching_plan_attrs_from_audit(audit, changes)
    return false if teaching_plan_attrs.blank?

    return false unless unity_matches?(teaching_plan_attrs['unity_id'])
    return false if @teacher_id.present? && teaching_plan_attrs['teacher_id'].to_i != @teacher_id.to_i
    return false unless discipline_id_matches_filter?(changes['discipline_id'])
    return false if @classroom_id.present? && !grade_matches_classroom?(teaching_plan_attrs['grade_id'])

    teaching_plan_year_in_range?(teaching_plan_attrs['year'])
  end

  def matches_knowledge_area_teaching_plan_changes?(changes, audit)
    teaching_plan_attrs = teaching_plan_attrs_from_audit(audit, changes)
    return false if teaching_plan_attrs.blank?

    return false unless unity_matches?(teaching_plan_attrs['unity_id'])
    return false if @teacher_id.present? && teaching_plan_attrs['teacher_id'].to_i != @teacher_id.to_i
    return false if @classroom_id.present? && !grade_matches_classroom?(teaching_plan_attrs['grade_id'])
    return false unless knowledge_area_ids_match_filter?(knowledge_area_ids_from_teaching_plan_audit(audit, changes))

    teaching_plan_year_in_range?(teaching_plan_attrs['year'])
  end

  def matches_discipline_lesson_plan_changes?(changes, audit)
    lesson_plan_attrs = lesson_plan_attrs_from_audit(audit, changes)
    return false if lesson_plan_attrs.blank?

    classroom = Classroom.find_by(id: lesson_plan_attrs['classroom_id'])
    return false unless unity_matches?(classroom&.unity_id)
    return false if @classroom_id.present? && lesson_plan_attrs['classroom_id'].to_i != @classroom_id.to_i
    return false if @teacher_id.present? && lesson_plan_attrs['teacher_id'].to_i != @teacher_id.to_i
    return false unless discipline_id_matches_filter?(changes['discipline_id'])

    lesson_plan_date_range_overlaps?(lesson_plan_attrs)
  end

  def matches_knowledge_area_lesson_plan_changes?(changes, audit)
    lesson_plan_attrs = lesson_plan_attrs_from_audit(audit, changes)
    return false if lesson_plan_attrs.blank?

    classroom = Classroom.find_by(id: lesson_plan_attrs['classroom_id'])
    return false unless unity_matches?(classroom&.unity_id)
    return false if @classroom_id.present? && lesson_plan_attrs['classroom_id'].to_i != @classroom_id.to_i
    return false if @teacher_id.present? && lesson_plan_attrs['teacher_id'].to_i != @teacher_id.to_i
    return false unless knowledge_area_ids_match_filter?(knowledge_area_ids_from_lesson_plan_audit(audit, changes))

    lesson_plan_date_range_overlaps?(lesson_plan_attrs)
  end

  def matches_daily_note_context?(context)
    return false unless unity_matches?(context[:unity_id])
    return false if @classroom_id.present? && context[:classroom_id].to_i != @classroom_id.to_i
    return false unless discipline_id_matches_filter?(context[:discipline_id])

    true
  end

  def teacher_linked_to_avaliation?(changes)
    Avaliation.by_teacher(@teacher_id)
              .where(id: changes['id'])
              .exists? ||
      TeacherDisciplineClassroom.exists?(
        teacher_id: @teacher_id,
        classroom_id: changes['classroom_id'],
        discipline_id: discipline_ids_for_teacher_link(changes['discipline_id'])
      )
  end

  def discipline_ids_for_teacher_link(discipline_id)
    records_by_knowledge_area? ? related_discipline_ids : discipline_id
  end

  def teacher_audit_matches?(audit)
    return true if @teacher_id.blank?

    user = audit.user
    return false unless user

    user.teacher_id.to_i == @teacher_id.to_i || user.assumed_teacher_id.to_i == @teacher_id.to_i
  end

  def build_destroyed_entry(audit)
    changes = audited_changes_hash(audit)
    label = destroyed_label(audit, changes)
    occurred_on = occurred_on_from_destroyed(audit, changes)
    avaliation_id = destroyed_avaliation_id(audit, changes)

    build_entry(
      auditable_type: audit.auditable_type,
      auditable_id: audit.auditable_id,
      record_type: record_type_for(audit.auditable_type),
      record: nil,
      occurred_on: occurred_on,
      label: label,
      avaliation_id: avaliation_id,
      **destroyed_context(audit, changes)
    )
  end

  def build_entry(auditable_type:, auditable_id:, record_type:, record:, occurred_on:, label:, **options)
    {
      auditable_type: auditable_type,
      auditable_id: auditable_id,
      record_type: record_type,
      record: record,
      occurred_on: occurred_on,
      label: label
    }.merge(options)
  end

  def deduplicate_entries(entries)
    entries.uniq { |entry| entry_key(entry) }
  end

  def entry_key(entry)
    entry[:entry_key_override] || [entry[:auditable_type], entry[:auditable_id]]
  end

  def fetch_audit_groups(entries)
    return {} if entries.blank?

    groups = {}

    entries.each do |entry|
      next if entry[:inline_audits].blank?

      groups[entry_key(entry)] = entry[:inline_audits]
    end

    regular_entries = entries.reject { |entry| entry[:inline_audits].present? }
    return groups if regular_entries.blank?

    auditable_types = regular_entries.map { |entry| entry[:auditable_type] }.uniq
    auditable_ids = regular_entries.map { |entry| entry[:auditable_id] }

    audits = Audited::Audit.where(auditable_type: auditable_types, auditable_id: auditable_ids)
                           .includes(:user)
                           .order(:created_at)

    audits.group_by { |audit| [audit.auditable_type, audit.auditable_id] }.each do |key, grouped_audits|
      groups[key] = grouped_audits
    end

    groups
  end

  def build_results(entries, audit_groups)
    entries.map do |entry|
      audits = audit_groups[entry_key(entry)] || []
      events = build_events(audits)
      record_exists = entry[:record].present?
      status = result_status(entry, record_exists)

      {
        auditable_type: entry[:auditable_type],
        auditable_id: entry[:auditable_id],
        record_type: entry[:record_type],
        record_type_label: record_type_label(entry[:record_type]),
        occurred_on: entry[:occurred_on],
        pedagogical_date: entry[:occurred_on],
        primary_at: primary_event_at(events),
        event_at: primary_event_at(events),
        label: entry[:label],
        detail: entry[:detail],
        record_exists: record_exists,
        status: status,
        avaliation_id: entry[:avaliation_id],
        events: events,
        summary: build_entry_summary(entry, events),
        verdict: build_verdict(entry, events, record_exists),
        classroom_id: entry[:classroom_id],
        classroom_name: entry[:classroom_name],
        discipline_id: entry[:discipline_id],
        discipline_name: entry[:discipline_name],
        class_number: entry[:class_number],
        period_label: entry[:period_label],
        teacher_id: entry[:teacher_id],
        teacher_name: entry[:teacher_name],
        completeness: entry[:completeness],
        history_id: entry[:history_id]
      }
    end.sort_by do |result|
      pedagogical = result[:occurred_on] || Date.new(0)
      event_time = result[:event_at] || Time.zone.at(0)
      [pedagogical, event_time, result[:label].to_s]
    end.reverse
  end

  def build_events(audits)
    audits.map do |audit|
      {
        action: audit.action,
        action_label: AuditedAction.t(audit.action),
        at: audit.created_at,
        user_name: audit.user&.to_s || I18n.t('services.record_audit_trail_summary.system_user'),
        detail: event_detail(audit)
      }
    end
  end

  def event_detail(audit)
    return nil unless audit.auditable_type == 'DailyNoteStudent' && audit.action == 'update'

    changes = audited_changes_hash(audit)
    return nil unless changes.key?('note')

    old_note, new_note = Array(changes['note'])
    format_note_change(old_note, new_note)
  end

  def format_note_change(old_note, new_note)
    if old_note.blank? && new_note.present?
      I18n.t('services.record_audit_trail_summary.note_change.launched', note: format_note(new_note))
    elsif old_note.present? && new_note.blank?
      I18n.t('services.record_audit_trail_summary.note_change.cleared', note: format_note(old_note))
    else
      I18n.t(
        'services.record_audit_trail_summary.note_change.changed',
        old_note: format_note(old_note),
        new_note: format_note(new_note)
      )
    end
  end

  def format_note(note)
    note.present? ? format('%.1f', note.to_f) : '-'
  end

  def build_entry_summary(entry, events)
    if entry[:auditable_type] == GRADE_NOTE_BATCH_TYPE
      return build_grade_batch_summary(entry, events)
    end

    build_summary(events)
  end

  def build_grade_batch_summary(entry, events)
    return I18n.t('services.record_audit_trail_summary.no_events') if events.blank?

    event = events.first
    I18n.t(
      'services.record_audit_trail_summary.event_line',
      action: AuditedAction.t('update'),
      datetime: I18n.l(event[:at], format: :compressed),
      user: event[:user_name]
    ) + " — #{entry[:label]}"
  end

  def build_summary(events)
    return I18n.t('services.record_audit_trail_summary.no_events') if events.blank?

    events.map do |event|
      line = I18n.t(
        'services.record_audit_trail_summary.event_line',
        action: event[:action_label],
        datetime: I18n.l(event[:at], format: :compressed),
        user: event[:user_name]
      )
      event[:detail].present? ? "#{line} (#{event[:detail]})" : line
    end.join('; ')
  end

  def build_verdict(entry, events, record_exists)
    if entry[:auditable_type] == GRADE_NOTE_BATCH_TYPE
      return build_grade_batch_verdict(entry, events)
    end

    if entry[:auditable_type] == CONCEPTUAL_EXAM_BATCH_TYPE
      return build_opinion_batch_verdict(entry, events)
    end

    create_event = events.find { |event| event[:action] == 'create' }
    destroy_event = events.find { |event| event[:action] == 'destroy' }
    update_events = events.select { |event| event[:action] == 'update' }

    if events.blank?
      if record_exists && incomplete_frequency?(entry)
        return incomplete_frequency_verdict(entry, nil)
      end
      if record_exists && incomplete_opinion?(entry)
        return incomplete_opinion_verdict(entry, nil)
      end

      return I18n.t('services.record_audit_trail_summary.verdict.no_audit_trail') if record_exists

      return I18n.t('services.record_audit_trail_summary.verdict.never_persisted')
    end

    if entry[:auditable_type] == 'DailyNote' && destroy_event.present?
      return I18n.t(
        'services.record_audit_trail_summary.verdict.daily_note_destroyed',
        datetime: I18n.l(destroy_event[:at], format: :compressed),
        user: destroy_event[:user_name]
      )
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

    if entry[:record_type] == 'avaliation' && create_event.present? && record_exists
      test_date = entry[:occurred_on]
      return I18n.t(
        'services.record_audit_trail_summary.verdict.avaliation_created_in_period',
        datetime: I18n.l(create_event[:at], format: :compressed),
        user: create_event[:user_name],
        test_date: I18n.l(test_date)
      )
    end

    if record_exists && incomplete_frequency?(entry)
      last_change = update_events.last || create_event
      return incomplete_frequency_verdict(entry, last_change)
    end

    if record_exists && incomplete_opinion?(entry)
      last_change = update_events.last || create_event
      return incomplete_opinion_verdict(entry, last_change)
    end

    if create_event.present? && record_exists
      if incomplete_opinion?(entry)
        last_change = update_events.last || create_event
        return incomplete_opinion_verdict(entry, last_change)
      end

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

  def build_grade_batch_verdict(entry, events)
    stats = entry[:grade_batch_stats] || {}
    event = events.first
    return I18n.t('services.record_audit_trail_summary.verdict.unknown') if event.blank?

    common = {
      count: stats[:total],
      datetime: I18n.l(event[:at], format: :compressed),
      user: event[:user_name]
    }

    if stats[:launched].positive? && stats[:cleared].zero?
      return I18n.t(
        'services.record_audit_trail_summary.verdict.grades_launched',
        **common,
        range: stats[:note_range]
      )
    end

    if stats[:cleared].positive? && stats[:launched].zero?
      return I18n.t(
        'services.record_audit_trail_summary.verdict.grades_cleared',
        **common
      )
    end

    I18n.t(
      'services.record_audit_trail_summary.verdict.grades_mixed',
      **common,
      launched: stats[:launched],
      cleared: stats[:cleared]
    )
  end

  def primary_event_at(events)
    return nil if events.blank?

    events.map { |event| event[:at] }.compact.max
  end

  def frequency_label(record)
    parts = [
      record.discipline&.to_s || I18n.t('services.record_audit_trail_summary.general_frequency'),
      record.classroom&.to_s,
      class_number_label(record.class_number),
      period_label_for(record.period),
      (I18n.l(record.frequency_date) if record.frequency_date),
      teacher_name_label(record.teacher)
    ]
    parts.compact.reject(&:blank?).join(' — ')
  end

  def discipline_content_label(record)
    parts = [
      record.discipline&.to_s,
      record.classroom&.to_s,
      class_number_label(record.class_number),
      (I18n.l(record.content_record.record_date) if record.content_record&.record_date),
      teacher_name_label(record.content_record&.teacher)
    ]
    parts.compact.reject(&:blank?).join(' — ')
  end

  def knowledge_area_content_label(record)
    areas = record.knowledge_areas.map(&:to_s).join(', ')
    parts = [
      areas.presence,
      record.classroom&.to_s,
      (I18n.l(record.content_record.record_date) if record.content_record&.record_date),
      teacher_name_label(record.content_record&.teacher)
    ]
    parts.compact.reject(&:blank?).join(' — ')
  end

  def discipline_teaching_plan_label(record)
    teaching_plan = record.teaching_plan
    term = teaching_plan.school_term_type_step_humanize.presence || teaching_plan.school_term_type&.to_s || '-'
    "#{record.discipline} — #{teaching_plan.grade} — #{term} — #{teaching_plan.year}"
  end

  def knowledge_area_teaching_plan_label(record)
    teaching_plan = record.teaching_plan
    areas = record.knowledge_areas.map(&:to_s).join(', ')
    term = teaching_plan.school_term_type_step_humanize.presence || teaching_plan.school_term_type&.to_s || '-'
    "#{areas} — #{teaching_plan.grade} — #{term} — #{teaching_plan.year}"
  end

  def discipline_lesson_plan_label(record)
    lesson_plan = record.lesson_plan
    "#{record.discipline} — #{lesson_plan.classroom} — #{I18n.l(lesson_plan.start_at.to_date)} a #{I18n.l(lesson_plan.end_at.to_date)}"
  end

  def knowledge_area_lesson_plan_label(record)
    lesson_plan = record.lesson_plan
    areas = record.knowledge_areas.map(&:to_s).join(', ')
    "#{areas} — #{lesson_plan.classroom} — #{I18n.l(lesson_plan.start_at.to_date)} a #{I18n.l(lesson_plan.end_at.to_date)}"
  end

  def teaching_plan_occurred_on(teaching_plan)
    [teaching_plan.updated_at, teaching_plan.created_at].compact.max.to_date
  end

  def avaliation_label(record)
    "#{record} — #{record.discipline} — #{I18n.l(record.test_date)}"
  end

  def avaliation_label_from_changes(changes)
    discipline_name = Discipline.find_by(id: changes['discipline_id'])&.to_s || '-'
    date = parse_date(changes['test_date'])
    description = changes['description'].presence || '-'
    "#{description} — #{discipline_name} — #{I18n.l(date)}"
  end

  def daily_note_active_label(avaliation)
    I18n.t(
      'services.record_audit_trail_summary.daily_note_label.active',
      avaliation: avaliation.to_s,
      discipline: avaliation.discipline.to_s,
      classroom: avaliation.classroom.to_s,
      date: I18n.l(avaliation.test_date)
    )
  end

  def grade_batch_label(context, stats)
    avaliation = context[:avaliation]
    avaliation_name = avaliation&.to_s || I18n.t('services.record_audit_trail_summary.removed_record')
    discipline_name = context[:discipline_name] || '-'
    classroom_name = context[:classroom_name] || '-'
    common = {
      count: stats[:total],
      avaliation: avaliation_name,
      discipline: discipline_name,
      classroom: classroom_name
    }

    if stats[:launched].positive? && stats[:cleared].zero?
      return I18n.t(
        'services.record_audit_trail_summary.grade_batch_label.launched',
        **common,
        range: stats[:note_range]
      )
    end

    if stats[:cleared].positive? && stats[:launched].zero?
      return I18n.t(
        'services.record_audit_trail_summary.grade_batch_label.cleared',
        **common
      )
    end

    I18n.t(
      'services.record_audit_trail_summary.grade_batch_label.mixed',
      **common,
      launched: stats[:launched],
      cleared: stats[:cleared]
    )
  end

  def grade_batch_stats(audits)
    launched = 0
    cleared = 0
    notes = []

    audits.each do |audit|
      changes = audited_changes_hash(audit)
      old_note, new_note = Array(changes['note'])

      if old_note.blank? && new_note.present?
        launched += 1
        notes << new_note.to_f
      elsif old_note.present? && new_note.blank?
        cleared += 1
      elsif old_note.present? && new_note.present?
        launched += 1
        notes << new_note.to_f
      end
    end

    {
      total: audits.size,
      launched: launched,
      cleared: cleared,
      note_range: note_range_label(notes)
    }
  end

  def note_range_label(notes)
    return '-' if notes.blank?

    min_note = notes.min
    max_note = notes.max
    min_label = format('%.1f', min_note)
    max_label = format('%.1f', max_note)

    min_label == max_label ? min_label : "#{min_label} a #{max_label}"
  end

  def grade_batch_group_key(audit)
    changes = audited_changes_hash(audit)
    daily_note_id = changes['daily_note_id']
    [daily_note_id, audit.user_id, audit.created_at.change(sec: 0, usec: 0)]
  end

  def daily_note_id_from_audit(audit)
    audited_changes_hash(audit)['daily_note_id']
  end

  def note_audited_change?(audit)
    changes = audited_changes_hash(audit)
    return false unless changes.key?('note')

    old_note, new_note = Array(changes['note'])
    old_note.to_s != new_note.to_s
  end

  def daily_note_context(daily_note_id)
    return nil if daily_note_id.blank?

    @daily_note_context_cache ||= {}
    @daily_note_context_cache[daily_note_id] ||= begin
      record = DailyNote.find_by(id: daily_note_id)
      if record
        avaliation = record.avaliation
        {
          daily_note_id: daily_note_id,
          avaliation: avaliation,
          classroom_id: record.classroom_id,
          discipline_id: record.discipline_id,
          unity_id: record.unity_id,
          discipline_name: avaliation&.discipline&.to_s,
          classroom_name: avaliation&.classroom&.to_s
        }
      else
        audit = Audited::Audit.where(auditable_type: 'DailyNote', auditable_id: daily_note_id)
                              .order(created_at: :desc)
                              .first
        changes = audit ? audited_changes_hash(audit) : {}
        avaliation = avaliation_from_changes(changes)
        classroom = Classroom.find_by(id: changes['classroom_id'] || avaliation&.classroom_id)

        {
          daily_note_id: daily_note_id,
          avaliation: avaliation,
          classroom_id: changes['classroom_id'] || avaliation&.classroom_id,
          discipline_id: changes['discipline_id'] || avaliation&.discipline_id,
          unity_id: changes['unity_id'] || classroom&.unity_id,
          discipline_name: Discipline.find_by(id: changes['discipline_id'] || avaliation&.discipline_id)&.to_s,
          classroom_name: classroom&.to_s || avaliation&.classroom&.to_s
        }
      end
    end
  end

  def avaliation_from_changes(changes)
    Avaliation.find_by(id: changes['avaliation_id'])
  end

  def daily_notes_filtered_scope
    avaliations = Avaliation.by_test_date_between(@start_date, @end_date)
    avaliations = avaliations.by_unity_id(@unity_id) if @unity_id.present?
    avaliations = avaliations.by_classroom_id(@classroom_id) if @classroom_id.present?
    avaliations = apply_discipline_filter(avaliations)
    avaliations = avaliations.by_teacher(@teacher_id) if @teacher_id.present?

    DailyNote.joins(:avaliation).merge(avaliations).distinct
  end

  def destroyed_label(audit, changes)
    case audit.auditable_type
    when 'DailyFrequency'
      discipline_name = Discipline.find_by(id: changes['discipline_id'])&.to_s ||
                        I18n.t('services.record_audit_trail_summary.general_frequency')
      classroom_name = Classroom.find_by(id: changes['classroom_id'])&.to_s || '-'
      date = parse_date(changes['frequency_date'])
      teacher_name = Teacher.find_by(id: changes['owner_teacher_id'])&.to_s
      parts = [
        discipline_name,
        classroom_name,
        class_number_label(changes['class_number']),
        period_label_for(changes['period']),
        (I18n.l(date) if date),
        teacher_name_label_from_name(teacher_name),
        "(#{I18n.t('services.record_audit_trail_summary.removed')})"
      ]
      parts.compact.reject(&:blank?).join(' — ')
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
      avaliation_label_from_changes(changes) + " (#{I18n.t('services.record_audit_trail_summary.removed')})"
    when 'DailyNote'
      avaliation = avaliation_from_changes(changes)
      I18n.t(
        'services.record_audit_trail_summary.daily_note_label.removed',
        avaliation: avaliation&.to_s || '-',
        discipline: Discipline.find_by(id: changes['discipline_id'])&.to_s || '-',
        classroom: Classroom.find_by(id: changes['classroom_id'])&.to_s || '-',
        date: I18n.l(avaliation&.test_date || audit.created_at.to_date)
      )
    when 'DisciplineTeachingPlan'
      discipline_teaching_plan_destroyed_label(changes, audit)
    when 'KnowledgeAreaTeachingPlan'
      knowledge_area_teaching_plan_destroyed_label(changes, audit)
    when 'DisciplineLessonPlan'
      discipline_lesson_plan_destroyed_label(changes, audit)
    when 'KnowledgeAreaLessonPlan'
      knowledge_area_lesson_plan_destroyed_label(changes, audit)
    when 'DescriptiveExam'
      classroom_name = Classroom.find_by(id: changes['classroom_id'])&.to_s || '-'
      discipline_name = Discipline.find_by(id: changes['discipline_id'])&.to_s
      date = parse_date(changes['recorded_at'])
      parts = [
        I18n.t('services.record_audit_trail_summary.opinion_descriptive'),
        discipline_name,
        classroom_name,
        (I18n.l(date) if date),
        "(#{I18n.t('services.record_audit_trail_summary.removed')})"
      ]
      parts.compact.reject(&:blank?).join(' — ')
    when 'ConceptualExam'
      classroom_name = Classroom.find_by(id: changes['classroom_id'])&.to_s || '-'
      date = parse_date(changes['recorded_at'])
      parts = [
        I18n.t('services.record_audit_trail_summary.opinion_conceptual'),
        classroom_name,
        (I18n.l(date) if date),
        "(#{I18n.t('services.record_audit_trail_summary.removed')})"
      ]
      parts.compact.reject(&:blank?).join(' — ')
    else
      I18n.t('services.record_audit_trail_summary.removed_record')
    end
  end

  def destroyed_avaliation_id(audit, changes)
    case audit.auditable_type
    when 'Avaliation' then audit.auditable_id
    when 'DailyNote' then changes['avaliation_id']
    end
  end

  def occurred_on_from_destroyed(audit, changes)
    case audit.auditable_type
    when 'DailyFrequency' then parse_date(changes['frequency_date'])
    when 'Avaliation' then parse_date(changes['test_date'])
    when 'DailyNote'
      avaliation = avaliation_from_changes(changes)
      avaliation&.test_date || audit.created_at.to_date
    when 'DisciplineContentRecord', 'KnowledgeAreaContentRecord'
      content_attrs = changes['content_record'] || content_record_attrs_from_audit(audit, changes)
      parse_date(content_attrs['record_date'])
    when 'DisciplineTeachingPlan', 'KnowledgeAreaTeachingPlan'
      teaching_plan_attrs = teaching_plan_attrs_from_audit(audit, changes)
      parse_date(teaching_plan_attrs['updated_at']) ||
        parse_date(teaching_plan_attrs['created_at']) ||
        teaching_plan_year_to_date(teaching_plan_attrs['year']) ||
        audit.created_at.to_date
    when 'DisciplineLessonPlan', 'KnowledgeAreaLessonPlan'
      lesson_plan_attrs = lesson_plan_attrs_from_audit(audit, changes)
      parse_date(lesson_plan_attrs['start_at']) || audit.created_at.to_date
    when 'DescriptiveExam', 'ConceptualExam'
      parse_date(changes['recorded_at']) || audit.created_at.to_date
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

  def teaching_plan_attrs_from_audit(audit, changes)
    nested = changes['teaching_plan']
    return nested if nested.is_a?(Hash) && nested['unity_id'].present?

    teaching_plan_id = changes['teaching_plan_id'] || nested&.dig('id')
    return {} if teaching_plan_id.blank?

    teaching_plan_audit = Audited::Audit.where(auditable_type: 'TeachingPlan', auditable_id: teaching_plan_id)
                                        .order(created_at: :desc)
                                        .first

    audited_changes_hash(teaching_plan_audit) if teaching_plan_audit
  end

  def lesson_plan_attrs_from_audit(audit, changes)
    nested = changes['lesson_plan']
    return nested if nested.is_a?(Hash) && nested['classroom_id'].present?

    lesson_plan_id = changes['lesson_plan_id'] || nested&.dig('id')
    return {} if lesson_plan_id.blank?

    lesson_plan_audit = Audited::Audit.where(auditable_type: 'LessonPlan', auditable_id: lesson_plan_id)
                                      .order(created_at: :desc)
                                      .first

    audited_changes_hash(lesson_plan_audit) if lesson_plan_audit
  end

  def discipline_teaching_plan_destroyed_label(changes, audit)
    teaching_plan_attrs = teaching_plan_attrs_from_audit(audit, changes)
    discipline_name = Discipline.find_by(id: changes['discipline_id'])&.to_s || '-'
    grade_name = Grade.find_by(id: teaching_plan_attrs['grade_id'])&.to_s || '-'
    year = teaching_plan_attrs['year'] || '-'
    term = school_term_label_from_changes(teaching_plan_attrs)

    "#{discipline_name} — #{grade_name} — #{term} — #{year} (#{I18n.t('services.record_audit_trail_summary.removed')})"
  end

  def knowledge_area_teaching_plan_destroyed_label(changes, audit)
    teaching_plan_attrs = teaching_plan_attrs_from_audit(audit, changes)
    grade_name = Grade.find_by(id: teaching_plan_attrs['grade_id'])&.to_s || '-'
    year = teaching_plan_attrs['year'] || '-'
    term = school_term_label_from_changes(teaching_plan_attrs)
    areas = knowledge_area_names_from_teaching_plan_audit(audit, changes)

    "#{areas} — #{grade_name} — #{term} — #{year} (#{I18n.t('services.record_audit_trail_summary.removed')})"
  end

  def discipline_lesson_plan_destroyed_label(changes, audit)
    lesson_plan_attrs = lesson_plan_attrs_from_audit(audit, changes)
    discipline_name = Discipline.find_by(id: changes['discipline_id'])&.to_s || '-'
    classroom_name = Classroom.find_by(id: lesson_plan_attrs['classroom_id'])&.to_s || '-'
    date_range = lesson_plan_date_range_label(lesson_plan_attrs)

    "#{discipline_name} — #{classroom_name} — #{date_range} (#{I18n.t('services.record_audit_trail_summary.removed')})"
  end

  def knowledge_area_lesson_plan_destroyed_label(changes, audit)
    lesson_plan_attrs = lesson_plan_attrs_from_audit(audit, changes)
    classroom_name = Classroom.find_by(id: lesson_plan_attrs['classroom_id'])&.to_s || '-'
    date_range = lesson_plan_date_range_label(lesson_plan_attrs)
    areas = knowledge_area_names_from_lesson_plan_audit(audit, changes)

    "#{areas} — #{classroom_name} — #{date_range} (#{I18n.t('services.record_audit_trail_summary.removed')})"
  end

  def lesson_plan_date_range_label(lesson_plan_attrs)
    start_at = parse_date(lesson_plan_attrs['start_at'])
    end_at = parse_date(lesson_plan_attrs['end_at'])
    return '-' if start_at.blank? && end_at.blank?
    return I18n.l(start_at) if end_at.blank?
    return I18n.l(end_at) if start_at.blank?

    "#{I18n.l(start_at)} a #{I18n.l(end_at)}"
  end

  def school_term_label_from_changes(teaching_plan_attrs)
    step_id = teaching_plan_attrs['school_term_type_step_id']
    type_id = teaching_plan_attrs['school_term_type_id']

    if step_id.present?
      SchoolTermTypeStep.find_by(id: step_id)&.to_s
    elsif type_id.present?
      SchoolTermType.find_by(id: type_id)&.to_s
    else
      '-'
    end
  end

  def knowledge_area_names_from_teaching_plan_audit(audit, changes)
    knowledge_area_ids = knowledge_area_ids_from_teaching_plan_audit(audit, changes)
    return '-' if knowledge_area_ids.blank?

    KnowledgeArea.where(id: knowledge_area_ids).map(&:to_s).join(', ')
  end

  def knowledge_area_names_from_lesson_plan_audit(audit, changes)
    knowledge_area_ids = knowledge_area_ids_from_lesson_plan_audit(audit, changes)
    return '-' if knowledge_area_ids.blank?

    KnowledgeArea.where(id: knowledge_area_ids).map(&:to_s).join(', ')
  end

  def knowledge_area_ids_from_teaching_plan_audit(audit, changes)
    nested = changes['knowledge_area_teaching_plan_knowledge_areas']
    return nested.map { |item| item['knowledge_area_id'] }.compact if nested.is_a?(Array)

    KnowledgeAreaTeachingPlanKnowledgeArea.where(knowledge_area_teaching_plan_id: audit.auditable_id)
                                          .pluck(:knowledge_area_id)
  end

  def knowledge_area_ids_from_lesson_plan_audit(audit, changes)
    nested = changes['knowledge_area_lesson_plan_knowledge_areas']
    return nested.map { |item| item['knowledge_area_id'] }.compact if nested.is_a?(Array)

    KnowledgeAreaLessonPlanKnowledgeArea.where(knowledge_area_lesson_plan_id: audit.auditable_id)
                                        .pluck(:knowledge_area_id)
  end

  def knowledge_area_ids_from_content_audit(audit, changes)
    nested = changes['knowledge_areas']
    if nested.is_a?(Array)
      return nested.map { |item| item['id'] || item['knowledge_area_id'] }.compact
    end

    ids = changes['knowledge_area_ids']
    if ids.is_a?(String)
      return ids.split(',').map(&:to_i)
    elsif ids.present?
      return Array(ids)
    end

    KnowledgeAreaContentRecord.unscoped.find_by(id: audit.auditable_id)&.knowledge_areas&.pluck(:id)
  end

  def apply_discipline_filter(scope)
    return scope if @discipline_id.blank?

    scope.where(discipline_id: discipline_ids_for_filter)
  end

  def apply_frequency_discipline_filter(scope)
    return scope if @discipline_id.blank?

    if records_by_knowledge_area?
      scope.where(discipline_id: related_discipline_ids + [nil])
    else
      scope.where(discipline_id: @discipline_id)
    end
  end

  def apply_knowledge_area_filter(scope, scope_name = :by_knowledge_area_id)
    return scope if selected_knowledge_area_id.blank?

    table_name = scope.klass.table_name
    ids = scope.public_send(scope_name, selected_knowledge_area_id)
               .distinct
               .pluck("#{table_name}.id")

    scope.klass.where(id: ids)
  end

  def discipline_id_matches_filter?(discipline_id, allow_blank: false)
    return true if @discipline_id.blank?
    return true if allow_blank && discipline_id.blank? && records_by_knowledge_area?

    discipline_ids_for_filter.map(&:to_i).include?(discipline_id.to_i)
  end

  def knowledge_area_ids_match_filter?(knowledge_area_ids)
    return true if selected_knowledge_area_id.blank?
    return records_by_knowledge_area? if knowledge_area_ids.blank?

    Array(knowledge_area_ids).map(&:to_i).include?(selected_knowledge_area_id.to_i)
  end

  def selected_discipline
    return if @discipline_id.blank?

    @selected_discipline ||= Discipline.find_by(id: @discipline_id)
  end

  def selected_knowledge_area_id
    selected_discipline&.knowledge_area_id
  end

  def records_by_knowledge_area?
    discipline = selected_discipline
    return false unless discipline

    discipline.grouper? || discipline.descriptor? || discipline.knowledge_area&.group_descriptors?
  end

  def related_discipline_ids
    @related_discipline_ids ||= begin
      knowledge_area_id = selected_knowledge_area_id

      if knowledge_area_id.blank?
        [@discipline_id.to_i]
      else
        Discipline.where(knowledge_area_id: knowledge_area_id).pluck(:id)
      end
    end
  end

  def discipline_ids_for_filter
    records_by_knowledge_area? ? related_discipline_ids : [@discipline_id]
  end

  def classroom_grade_ids
    @classroom_grade_ids ||= ClassroomsGrade.by_classroom_id(@classroom_id).pluck(:grade_id)
  end

  def grade_matches_classroom?(grade_id)
    return true if @classroom_id.blank? || grade_id.blank?

    classroom_grade_ids.include?(grade_id.to_i)
  end

  def teaching_plan_year_in_range?(year)
    return false if year.blank?

    year.to_i.between?(@start_date.year, @end_date.year)
  end

  def teaching_plan_year_to_date(year)
    return nil if year.blank?

    Date.new(year.to_i, 1, 1)
  rescue ArgumentError
    nil
  end

  def lesson_plan_date_range_overlaps?(lesson_plan_attrs)
    start_at = parse_date(lesson_plan_attrs['start_at'])
    end_at = parse_date(lesson_plan_attrs['end_at'])
    return false if start_at.blank? || end_at.blank?

    start_at <= @end_date && end_at >= @start_date
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

  def date_matches_filter?(value, audit = nil)
    return true if frequency_date_in_range?(value)
    return true if audit && audit.created_at.to_date.between?(@start_date, @end_date)

    false
  end

  def destroy_audit_search_period
    end_at = [@end_date, Date.current].max
    @start_date.beginning_of_day..end_at.end_of_day
  end

  def result_status(entry, record_exists)
    return 'removed' unless record_exists
    return 'incomplete' if incomplete_frequency?(entry) || incomplete_opinion?(entry)

    'active'
  end

  def incomplete_frequency?(entry)
    completeness = entry[:completeness]
    return false if completeness.blank?

    completeness[:unmarked].to_i.positive? || completeness[:total].to_i.zero?
  end

  def incomplete_frequency_verdict(entry, event)
    completeness = entry[:completeness] || {}

    if completeness[:total].to_i.zero?
      if event.present?
        return I18n.t(
          'services.record_audit_trail_summary.verdict.frequency_without_students',
          datetime: I18n.l(event[:at], format: :compressed),
          user: event[:user_name]
        )
      end

      return I18n.t('services.record_audit_trail_summary.verdict.frequency_without_students_no_audit')
    end

    common = {
      marked: completeness[:marked],
      unmarked: completeness[:unmarked],
      total: completeness[:total]
    }

    if event.present?
      return I18n.t(
        'services.record_audit_trail_summary.verdict.frequency_incomplete',
        **common,
        datetime: I18n.l(event[:at], format: :compressed),
        user: event[:user_name]
      )
    end

    I18n.t('services.record_audit_trail_summary.verdict.frequency_incomplete_no_audit', **common)
  end

  def incomplete_opinion?(entry)
    return false unless entry[:record_type] == 'opinion'

    completeness = entry[:completeness]
    return false if completeness.blank?

    completeness[:unmarked].to_i.positive? || completeness[:total].to_i.zero?
  end

  def incomplete_opinion_verdict(entry, event)
    completeness = entry[:completeness] || {}
    common = {
      marked: completeness[:marked],
      unmarked: completeness[:unmarked],
      total: completeness[:total]
    }

    if event.present?
      return I18n.t(
        'services.record_audit_trail_summary.verdict.opinion_incomplete',
        **common,
        datetime: I18n.l(event[:at], format: :compressed),
        user: event[:user_name]
      )
    end

    I18n.t('services.record_audit_trail_summary.verdict.opinion_incomplete_no_audit', **common)
  end

  def build_opinion_batch_verdict(entry, events)
    event = events.max_by { |item| item[:at] }
    return incomplete_opinion_verdict(entry, event) if incomplete_opinion?(entry) && entry[:record].present?

    return I18n.t('services.record_audit_trail_summary.verdict.unknown') if event.blank?

    if entry[:record].blank?
      return I18n.t(
        'services.record_audit_trail_summary.verdict.destroyed',
        datetime: I18n.l(event[:at], format: :compressed),
        user: event[:user_name]
      )
    end

    I18n.t(
      'services.record_audit_trail_summary.verdict.active',
      datetime: I18n.l(event[:at], format: :compressed),
      user: event[:user_name]
    )
  end

  def frequency_context(record)
    completeness = frequency_completeness(record)

    {
      classroom_id: record.classroom_id,
      classroom_name: record.classroom&.to_s,
      discipline_id: record.discipline_id,
      discipline_name: record.discipline&.to_s || I18n.t('services.record_audit_trail_summary.general_frequency'),
      class_number: record.class_number,
      period_label: period_label_for(record.period),
      teacher_id: record.owner_teacher_id,
      teacher_name: record.teacher&.to_s,
      completeness: completeness,
      detail: frequency_detail(completeness)
    }
  end

  def discipline_content_context(record)
    content_record = record.content_record

    {
      classroom_id: record.classroom_id,
      classroom_name: record.classroom&.to_s,
      discipline_id: record.discipline_id,
      discipline_name: record.discipline&.to_s,
      class_number: record.class_number,
      teacher_id: content_record&.teacher_id,
      teacher_name: content_record&.teacher&.to_s,
      detail: content_preview(content_record)
    }
  end

  def knowledge_area_content_context(record)
    content_record = record.content_record

    {
      classroom_id: record.classroom_id,
      classroom_name: record.classroom&.to_s,
      discipline_id: nil,
      discipline_name: record.knowledge_areas.map(&:to_s).join(', '),
      teacher_id: content_record&.teacher_id,
      teacher_name: content_record&.teacher&.to_s,
      detail: content_preview(content_record)
    }
  end

  def destroyed_context(_audit, changes)
    content_attrs = changes['content_record'] if changes['content_record'].is_a?(Hash)
    classroom_id = changes['classroom_id'] || content_attrs&.fetch('classroom_id', nil)
    teacher_id = changes['owner_teacher_id'] || content_attrs&.fetch('teacher_id', nil)

    {
      classroom_id: classroom_id,
      classroom_name: Classroom.find_by(id: classroom_id)&.to_s,
      discipline_id: changes['discipline_id'],
      discipline_name: Discipline.find_by(id: changes['discipline_id'])&.to_s,
      class_number: changes['class_number'],
      period_label: period_label_for(changes['period']),
      teacher_id: teacher_id,
      teacher_name: Teacher.find_by(id: teacher_id)&.to_s
    }
  end

  def frequency_completeness(record)
    students = frequency_active_students(record)
    unmarked = students.count { |student| student.read_attribute(:present).nil? }

    {
      total: students.size,
      unmarked: unmarked,
      marked: students.size - unmarked
    }
  end

  def frequency_active_students(record)
    students = record.students
    if students.loaded?
      students.select(&:active)
    else
      students.active.to_a
    end
  end

  def frequency_detail(completeness)
    return if completeness.blank?

    I18n.t(
      'services.record_audit_trail_summary.frequency_completeness',
      marked: completeness[:marked],
      total: completeness[:total]
    )
  end

  def content_preview(content_record)
    return if content_record.blank?

    titles = Array(content_record.contents).map(&:to_s).reject(&:blank?)
    parts = []
    if titles.present?
      preview = titles.first(3).join('; ')
      preview = "#{preview.truncate(120)}…" if titles.size > 3 && !preview.end_with?('…')
      parts << I18n.t('services.record_audit_trail_summary.content_preview', contents: preview)
    end

    activities = content_record.daily_activities_record.to_s.strip
    if activities.present?
      parts << I18n.t(
        'services.record_audit_trail_summary.activities_preview',
        activities: activities.truncate(120)
      )
    end

    parts.join(' ')
  end

  def class_number_label(class_number)
    return if class_number.blank?

    I18n.t('services.record_audit_trail_summary.class_number', number: class_number)
  end

  def period_label_for(period)
    return if period.blank?

    Periods.t(period)
  rescue StandardError
    period.to_s
  end

  def teacher_name_label(teacher)
    teacher_name_label_from_name(teacher&.to_s)
  end

  def teacher_name_label_from_name(name)
    return if name.blank?

    I18n.t('services.record_audit_trail_summary.owner_teacher', name: name)
  end

  def conceptual_exam_base_scope
    scope = ConceptualExam.with_discarded.joins(:classroom).where(classrooms: { unity_id: @unity_id })
    scope = scope.where(recorded_at: @start_date..@end_date)
    scope = scope.by_classroom_id(@classroom_id) if @classroom_id.present?
    scope
  end

  def apply_descriptive_discipline_filter(scope)
    return scope if @discipline_id.blank?

    if records_by_knowledge_area?
      scope.where(discipline_id: discipline_ids_for_filter + [nil])
    else
      apply_discipline_filter(scope)
    end
  end

  def apply_conceptual_discipline_filter(scope)
    return scope if @discipline_id.blank?

    scope.by_discipline(discipline_ids_for_filter)
  end

  def opinion_teacher_matches_classroom?(classroom_id)
    return true if @teacher_id.blank?
    return true if teacher_historically_linked_to_classroom?(classroom_id)

    false
  end

  def teacher_historically_linked_to_classroom?(classroom_id)
    return false if @teacher_id.blank? || classroom_id.blank?

    TeacherDisciplineClassroom.unscoped.exists?(
      teacher_id: @teacher_id,
      classroom_id: classroom_id,
      year: (@start_date.year..@end_date.year).to_a
    )
  end

  def descriptive_exam_persisted?(record)
    !record.respond_to?(:deleted_at) || record.deleted_at.blank?
  end

  def descriptive_exam_label(record)
    parts = [
      I18n.t('services.record_audit_trail_summary.opinion_descriptive'),
      record.discipline&.to_s,
      record.classroom&.to_s,
      step_number_label(record.step_number),
      (I18n.l(record.recorded_at) if record.recorded_at)
    ]
    parts.compact.reject(&:blank?).join(' — ')
  end

  def conceptual_exam_batch_label(sample, completeness)
    parts = [
      I18n.t(
        'services.record_audit_trail_summary.opinion_conceptual_batch',
        count: completeness[:total]
      ),
      sample.classroom&.to_s,
      step_number_label(sample.step_number),
      (I18n.l(sample.recorded_at) if sample.recorded_at)
    ]
    parts.compact.reject(&:blank?).join(' — ')
  end

  def step_number_label(step_number)
    return if step_number.blank? || step_number.to_i.zero?

    I18n.t('services.record_audit_trail_summary.step_number', number: step_number)
  end

  def descriptive_exam_context(record)
    completeness = descriptive_exam_completeness(record)

    {
      classroom_id: record.classroom_id,
      classroom_name: record.classroom&.to_s,
      discipline_id: record.discipline_id,
      discipline_name: record.discipline&.to_s,
      completeness: completeness,
      detail: opinion_completeness_detail(completeness)
    }
  end

  def descriptive_exam_completeness(record)
    students = Array(record.students)
    marked = students.count { |student| DescriptiveExamValue.present?(student.value) }

    {
      total: students.size,
      marked: marked,
      unmarked: students.size - marked
    }
  end

  def conceptual_exam_completeness(exams)
    marked = exams.count do |exam|
      exam.conceptual_exam_values.any? { |value| value.value.present? }
    end

    {
      total: exams.size,
      marked: marked,
      unmarked: exams.size - marked
    }
  end

  def opinion_completeness_detail(completeness)
    return if completeness.blank?

    I18n.t(
      'services.record_audit_trail_summary.opinion_completeness',
      marked: completeness[:marked],
      total: completeness[:total]
    )
  end

  def matches_descriptive_exam_changes?(changes, audit)
    classroom = Classroom.find_by(id: changes['classroom_id'])
    return false unless unity_matches?(classroom&.unity_id)
    return false if @classroom_id.present? && changes['classroom_id'].to_i != @classroom_id.to_i
    return false unless opinion_teacher_matches_classroom?(changes['classroom_id'])
    return false unless discipline_id_matches_filter?(changes['discipline_id'], allow_blank: true)

    date_matches_filter?(changes['recorded_at'], audit)
  end

  def matches_conceptual_exam_changes?(changes, audit)
    classroom = Classroom.find_by(id: changes['classroom_id'])
    return false unless unity_matches?(classroom&.unity_id)
    return false if @classroom_id.present? && changes['classroom_id'].to_i != @classroom_id.to_i
    return false unless opinion_teacher_matches_classroom?(changes['classroom_id'])

    date_matches_filter?(changes['recorded_at'], audit)
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
