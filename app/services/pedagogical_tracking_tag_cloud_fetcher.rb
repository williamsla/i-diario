class PedagogicalTrackingTagCloudFetcher
  DEFAULT_LIMIT = 40

  def initialize(grade_id:, discipline_id:, year:, unity_id: nil, unity_ids: nil, step_number: nil,
                 start_date: nil, end_date: nil, limit: DEFAULT_LIMIT)
    @grade_id = grade_id
    @discipline_id = discipline_id
    @year = year
    @unity_id = unity_id
    @unity_ids = Array(unity_ids).presence
    @step_number = step_number
    @start_date = start_date
    @end_date = end_date
    @limit = limit
  end

  def fetch
    {
      contents: tags_for(ContentRecordsContent, :content, Content.table_name),
      objectives: tags_for(ObjectivesContentRecord, :objective, Objective.table_name)
    }
  end

  private

  def tags_for(join_model, association, table_name)
    normalized_description = normalized_description_sql(table_name)
    records = join_model
      .joins(association)
      .joins(content_record: [:discipline_content_record, { classroom: :classrooms_grades }])
      .where(discipline_content_records: { discipline_id: @discipline_id })
      .where(classrooms_grades: { grade_id: @grade_id })
      .where(classrooms: { year: @year })

    records = apply_unity_filter(records)
    records = records.where('content_records.record_date >= ?', @start_date) if @start_date.present?
    records = records.where('content_records.record_date <= ?', @end_date) if @end_date.present?
    records = apply_step_filter(records) if @step_number.present?

    rows = records
      .group(normalized_description)
      .order(Arel.sql('usage_count DESC'))
      .limit(@limit)
      .pluck(
        Arel.sql("MIN(#{table_name}.description)"),
        Arel.sql('COUNT(DISTINCT content_records.id) AS usage_count')
      )

    add_weights(rows)
  end

  def apply_unity_filter(records)
    if @unity_id.present?
      records.where(classrooms: { unity_id: @unity_id })
    elsif @unity_ids.present?
      records.where(classrooms: { unity_id: @unity_ids })
    else
      records
    end
  end

  def apply_step_filter(records)
    records.where(<<-SQL.squish, step_number: @step_number.to_i, year: @year)
      EXISTS (
        SELECT 1
        FROM school_calendars sc
        INNER JOIN school_calendar_steps scs ON scs.school_calendar_id = sc.id
        WHERE sc.unity_id = classrooms.unity_id
          AND sc.year = :year
          AND scs.step_number = :step_number
          AND content_records.record_date BETWEEN scs.start_at AND scs.end_at
      )
    SQL
  end

  def normalized_description_sql(table_name)
    <<~SQL.squish
      LOWER(
        unaccent(
          regexp_replace(
            regexp_replace(TRIM(#{table_name}.description), '\\s+', ' ', 'g'),
            '[[:punct:]]+$', '', 'g'
          )
        )
      )
    SQL
  end

  def add_weights(rows)
    return [] if rows.empty?

    counts = rows.map { |(_, count)| count.to_i }
    minimum = Math.log(counts.min + 1)
    maximum = Math.log(counts.max + 1)

    rows.map do |label, count|
      count = count.to_i
      weight = if minimum == maximum
                 3
               else
                 1 + (((Math.log(count + 1) - minimum) / (maximum - minimum)) * 4).round
               end

      { label: label, count: count, weight: weight }
    end
  end
end
