# frozen_string_literal: true

class RecordAuditTrailPhrase
  def initialize(results:, neighbors:, stats:, pending_frequency_dates:, pending_content_dates:,
                 record_types:, start_date:, end_date:, allocation: nil, **)
    @results = results
    @neighbors = neighbors
    @stats = stats
    @pending_frequency_dates = pending_frequency_dates
    @pending_content_dates = pending_content_dates
    @record_types = record_types
    @start_date = start_date
    @end_date = end_date
    @allocation = allocation
  end

  def call
    sentences = []
    sentences << allocation_sentence
    sentences << scope_sentence
    sentences.concat(deleted_sentences)
    sentences.concat(incomplete_sentences)
    sentences.concat(missing_sentences)
    sentences.concat(active_sentences)
    sentences.concat(neighbor_sentences)
    sentences << empty_sentence if nothing_found?
    sentences.compact.join(' ')
  end

  private

  def allocation_sentence
    return if @allocation.blank?

    case @allocation[:status]
    when 'unlinked'
      extras = []
      extras << I18n.t('services.record_audit_trail_phrase.allocation_left_at', date: I18n.l(@allocation[:left_at])) if @allocation[:left_at].present?
      extras << I18n.t('services.record_audit_trail_phrase.allocation_discarded_at', date: I18n.l(@allocation[:discarded_at].to_date)) if @allocation[:discarded_at].present?
      I18n.t(
        'services.record_audit_trail_phrase.allocation_unlinked',
        teacher: @allocation[:teacher_name],
        classroom: @allocation[:classroom_name],
        details: extras.join(' ')
      )
    when 'missing'
      return if @results.blank?

      I18n.t(
        'services.record_audit_trail_phrase.allocation_missing',
        teacher: @allocation[:teacher_name],
        classroom: @allocation[:classroom_name]
      )
    end
  end

  def scope_sentence
    I18n.t(
      'services.record_audit_trail_phrase.scope',
      period: "#{I18n.l(@start_date)} a #{I18n.l(@end_date)}",
      types: type_labels
    )
  end

  def type_labels
    @record_types.map do |type|
      I18n.t("services.record_audit_trail_summary.record_types.#{type}", default: type)
    end.join(', ')
  end

  def deleted_sentences
    @results.select { |result| result[:status] == 'removed' }.map do |result|
      I18n.t(
        'services.record_audit_trail_phrase.deleted',
        type: result[:record_type_label],
        record: result[:label],
        verdict: result[:verdict]
      )
    end
  end

  def incomplete_sentences
    @results.select { |result| result[:status] == 'incomplete' }.map do |result|
      I18n.t(
        'services.record_audit_trail_phrase.incomplete',
        record: result[:label],
        verdict: result[:verdict]
      )
    end
  end

  def missing_sentences
    sentences = []
    if frequency_requested? && @pending_frequency_dates.present? && frequency_results.blank?
      sentences << I18n.t(
        'services.record_audit_trail_phrase.missing_frequency',
        dates: format_dates(@pending_frequency_dates)
      )
    elsif frequency_requested? && @pending_frequency_dates.present?
      sentences << I18n.t(
        'services.record_audit_trail_phrase.missing_frequency_partial',
        dates: format_dates(@pending_frequency_dates)
      )
    end

    if content_requested? && @pending_content_dates.present? && content_results.blank?
      sentences << I18n.t(
        'services.record_audit_trail_phrase.missing_content',
        dates: format_dates(@pending_content_dates)
      )
    elsif content_requested? && @pending_content_dates.present?
      sentences << I18n.t(
        'services.record_audit_trail_phrase.missing_content_partial',
        dates: format_dates(@pending_content_dates)
      )
    end
    sentences
  end

  def active_sentences
    active = @results.select { |result| result[:status] == 'active' }
    return [] if active.blank?

    grouped = active.group_by { |result| result[:record_type_label] }
    grouped.map do |type_label, items|
      I18n.t(
        'services.record_audit_trail_phrase.active',
        count: items.size,
        type: type_label,
        dates: format_dates(items.map { |item| item[:occurred_on] }.compact)
      )
    end
  end

  def neighbor_sentences
    return [] if @neighbors.blank?

    items = @neighbors.first(8).map do |result|
      reasons = Array(result[:mismatch_reasons]).map do |reason|
        I18n.t("services.record_audit_trail_phrase.reasons.#{reason}")
      end.join(', ')
      I18n.t(
        'services.record_audit_trail_phrase.neighbor_item',
        type: result[:record_type_label],
        record: result[:label],
        reasons: reasons
      )
    end

    [I18n.t('services.record_audit_trail_phrase.neighbors', items: items.join('; '))]
  end

  def empty_sentence
    I18n.t('services.record_audit_trail_phrase.empty')
  end

  def nothing_found?
    @results.blank? && @neighbors.blank? &&
      @pending_frequency_dates.blank? && @pending_content_dates.blank?
  end

  def frequency_requested?
    @record_types.include?('frequency')
  end

  def content_requested?
    @record_types.include?('content')
  end

  def frequency_results
    @results.select { |result| result[:record_type] == 'frequency' }
  end

  def content_results
    @results.select { |result| result[:record_type] == 'content' }
  end

  def format_dates(dates)
    dates.compact.map { |date| I18n.l(date.to_date) }.uniq.join(', ')
  end
end
