# frozen_string_literal: true

class RecordAuditTrailDiagnostic
  NEIGHBOR_WINDOW_DAYS = 3
  CALENDAR_RECORD_TYPES = %w[frequency content].freeze
  NEIGHBOR_RECORD_TYPES = %w[frequency content opinion].freeze

  def initialize(unity_id:, classroom_id:, teacher_id:, discipline_id:, start_date:, end_date:,
                 record_types:, school_year: nil)
    @unity_id = unity_id
    @classroom_id = classroom_id
    @teacher_id = teacher_id
    @discipline_id = discipline_id
    @start_date = start_date.to_date
    @end_date = end_date.to_date
    @record_types = Array(record_types)
    @school_year = school_year || @start_date.year
  end

  def call
    {
      results: results,
      neighbors: neighbors,
      calendar: calendar,
      phrase: phrase,
      stats: stats,
      allocation: allocation
    }
  end

  private

  def results
    @results ||= RecordAuditTrailSummary.new(
      unity_id: @unity_id,
      classroom_id: @classroom_id,
      teacher_id: @teacher_id,
      discipline_id: @discipline_id,
      start_date: @start_date,
      end_date: @end_date,
      record_types: @record_types
    ).call
  end

  def neighbors
    return [] if @teacher_id.blank?

    neighbor_types = @record_types & NEIGHBOR_RECORD_TYPES
    return [] if neighbor_types.blank?

    @neighbors ||= begin
      collected_keys = results.map { |result| [result[:auditable_type], result[:auditable_id]] }

      RecordAuditTrailSummary.new(
        unity_id: @unity_id,
        classroom_id: nil,
        teacher_id: @teacher_id,
        discipline_id: nil,
        start_date: @start_date - NEIGHBOR_WINDOW_DAYS,
        end_date: @end_date + NEIGHBOR_WINDOW_DAYS,
        record_types: neighbor_types
      ).call.reject { |result| collected_keys.include?([result[:auditable_type], result[:auditable_id]]) }
           .map { |result| result.merge(mismatch_reasons: mismatch_reasons(result)) }
           .select { |result| result[:mismatch_reasons].present? }
    end
  end

  def mismatch_reasons(result)
    reasons = []
    if @classroom_id.present? && result[:classroom_id].present? &&
       result[:classroom_id].to_i != @classroom_id.to_i
      reasons << 'other_classroom'
    end
    if @discipline_id.present?
      if result[:discipline_id].present?
        reasons << 'other_discipline' unless matching_discipline?(result)
      else
        reasons << 'other_discipline'
      end
    end
    if result[:occurred_on].present?
      date = result[:occurred_on].to_date
      reasons << 'nearby_date' unless date.between?(@start_date, @end_date)
    end
    reasons
  end

  def matching_discipline?(result)
    return true if @discipline_id.blank?
    return true if result[:discipline_id].blank?

    result[:discipline_id].to_i == @discipline_id.to_i
  end

  def calendar
    return [] unless calendar_record_types?
    return [] if interesting_dates.blank?

    interesting_dates.map { |date| calendar_row(date) }
  end

  def calendar_possible?
    @classroom_id.present? && @teacher_id.present?
  end

  def calendar_record_types?
    (@record_types & CALENDAR_RECORD_TYPES).present?
  end

  def interesting_dates
    @interesting_dates ||= begin
      dates = Set.new
      pending_records.each do |row|
        Array(row[:pending_frequency_dates]).each { |date| dates << date.to_date }
        Array(row[:pending_content_dates]).each { |date| dates << date.to_date }
      end
      results.each do |result|
        next unless CALENDAR_RECORD_TYPES.include?(result[:record_type])
        dates << result[:occurred_on].to_date if result[:occurred_on].present?
      end
      dates.select { |date| date.between?(@start_date, @end_date) }.sort
    end
  end

  def calendar_row(date)
    {
      date: date,
      frequency: calendar_cell(date, 'frequency', :pending_frequency_dates),
      content: calendar_cell(date, 'content', :pending_content_dates)
    }
  end

  def calendar_cell(date, record_type, pending_key)
    day_results = results.select do |result|
      result[:record_type] == record_type && result[:occurred_on].present? &&
        result[:occurred_on].to_date == date
    end
    pending_names = pending_records.select do |row|
      Array(row[pending_key]).map(&:to_date).include?(date)
    end.map { |row| row[:discipline_name] }.compact.uniq

    return { status: 'none', label: '—' } if day_results.blank? && pending_names.blank?

    {
      status: cell_status(day_results, pending_names),
      label: cell_label(day_results, pending_names)
    }
  end

  def cell_status(day_results, pending_names)
    if day_results.any? { |result| result[:status] == 'incomplete' }
      'incomplete'
    elsif day_results.any? { |result| result[:status] == 'active' } && pending_names.present?
      'mixed'
    elsif day_results.any? { |result| result[:status] == 'active' }
      'recorded'
    elsif day_results.any? { |result| result[:status] == 'removed' }
      'deleted'
    else
      'missing'
    end
  end

  def cell_label(day_results, pending_names)
    parts = day_results.map do |result|
      name = result[:discipline_name].presence || result[:label]
      "#{status_word(result[:status])}: #{name}"
    end
    pending_names.each do |name|
      next if day_results.any? { |result| result[:discipline_name].to_s == name.to_s }

      parts << I18n.t('services.record_audit_trail_diagnostic.cell.missing_item', name: name)
    end
    parts.join('; ')
  end

  def status_word(status)
    I18n.t("services.record_audit_trail_diagnostic.cell.#{status}", default: status.to_s)
  end

  def pending_records
    return [] unless calendar_possible?

    @pending_records ||= PendingRecordsCalculator.new(
      unity_id: @unity_id,
      classroom_id: @classroom_id,
      teacher_id: @teacher_id,
      discipline_id: @discipline_id,
      start_date: @start_date,
      end_date: @end_date,
      school_year: @school_year,
      include_dates: true
    ).calculate
  rescue StandardError => e
    Rails.logger.error("[RecordAuditTrailDiagnostic] #{e.class}: #{e.message}")
    []
  end

  def stats
    {
      total: results.size,
      active: results.count { |result| result[:status] == 'active' },
      incomplete: results.count { |result| result[:status] == 'incomplete' },
      removed: results.count { |result| result[:status] == 'removed' },
      no_audit: results.count { |result| result[:events].blank? && result[:record_exists] },
      neighbor_count: neighbors.size,
      pending_frequency_count: pending_dates(:pending_frequency_dates).size,
      pending_content_count: pending_dates(:pending_content_dates).size
    }
  end

  def pending_dates(key)
    pending_records.flat_map { |row| Array(row[key]) }.map(&:to_date).uniq.sort
  end

  def phrase
    RecordAuditTrailPhrase.new(
      results: results,
      neighbors: neighbors,
      stats: stats,
      pending_frequency_dates: pending_dates(:pending_frequency_dates),
      pending_content_dates: pending_dates(:pending_content_dates),
      record_types: @record_types,
      start_date: @start_date,
      end_date: @end_date,
      allocation: allocation
    ).call
  end

  def allocation
    @allocation ||= RecordAuditTrailTeacherLinks.allocation(
      classroom_id: @classroom_id,
      teacher_id: @teacher_id,
      year: @school_year
    )
  end
end
