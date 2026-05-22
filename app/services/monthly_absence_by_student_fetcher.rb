class MonthlyAbsenceByStudentFetcher
  Row = Struct.new(:unity_name, :classroom_description, :student_name, :absences_by_month)

  def self.call(unity_api_code:, year:, months:, grade_id: nil, classroom_id: nil, sort_by: MonthlyAbsenceReportSortOrders::STUDENT_NAME)
    new(
      unity_api_code: unity_api_code,
      year: year,
      months: months,
      grade_id: grade_id,
      classroom_id: classroom_id,
      sort_by: sort_by
    ).call
  end

  def initialize(unity_api_code:, year:, months:, grade_id: nil, classroom_id: nil, sort_by: MonthlyAbsenceReportSortOrders::STUDENT_NAME)
    @unity_api_code = unity_api_code.to_s
    @year = year.to_i
    @months = Array(months).map(&:to_i).uniq.sort
    @grade_id = grade_id.presence
    @classroom_id = classroom_id.presence
    @sort_by = normalize_sort_by(sort_by)
  end

  def call
    return [] if @months.empty?

    rows_hash = {}

    grouped_counts.each do |(unity_name, classroom_description, student_name, month), count|
      key = [unity_name, classroom_description, student_name]
      rows_hash[key] ||= {
        unity_name: unity_name,
        classroom_description: classroom_description,
        student_name: student_name,
        absences_by_month: {}
      }
      rows_hash[key][:absences_by_month][month] = count
    end

    rows = rows_hash.values.map do |data|
      Row.new(
        data[:unity_name],
        data[:classroom_description],
        data[:student_name],
        data[:absences_by_month]
      )
    end

    sort_rows(rows)
  end

  private

  def normalize_sort_by(sort_by)
    value = sort_by.to_s
    return MonthlyAbsenceReportSortOrders::ABSENCES_COUNT if value.in?(%w[absences_count faltas])

    MonthlyAbsenceReportSortOrders::STUDENT_NAME
  end

  def sort_rows(rows)
    if @sort_by == MonthlyAbsenceReportSortOrders::ABSENCES_COUNT
      rows.sort_by { |row| [-total_absences(row), row.classroom_description, row.student_name] }
    else
      rows.sort_by { |row| [row.classroom_description, row.student_name] }
    end
  end

  def total_absences(row)
    @months.sum { |month| row.absences_by_month[month] || 0 }
  end

  def grouped_counts
    @grouped_counts ||= begin
      query = DailyFrequencyStudent
              .joins(daily_frequency: { classroom: :unity })
              .joins(:student)
              .merge(DailyFrequencyStudent.absences)
              .where(unities: { api_code: @unity_api_code })
              .where('EXTRACT(YEAR FROM daily_frequencies.frequency_date) = ?', @year)
              .where('EXTRACT(MONTH FROM daily_frequencies.frequency_date) IN (?)', @months)

      query = apply_classroom_filters(query)

      query.group(
        'unities.name',
        'classrooms.description',
        'students.name',
        Arel.sql('EXTRACT(MONTH FROM daily_frequencies.frequency_date)::integer')
      )
           .count(Arel.sql('DISTINCT daily_frequencies.frequency_date'))
           .transform_keys do |(unity_name, classroom_description, student_name, month)|
        [unity_name, classroom_description, student_name, month]
      end
    end
  end

  def apply_classroom_filters(query)
    if @classroom_id.present?
      return query.where(daily_frequencies: { classroom_id: @classroom_id })
    end

    if @grade_id.present?
      classroom_ids = Classroom.joins(:unity)
                               .where(unities: { api_code: @unity_api_code })
                               .by_grade(@grade_id)
                               .by_year(@year)
                               .pluck(:id)
      return query.none if classroom_ids.empty?

      return query.where(daily_frequencies: { classroom_id: classroom_ids })
    end

    query
  end
end
