class MonthlyAbsenceByStudentReportForm
  include ActiveModel::Model

  attr_accessor :unity_id,
                :unity_api_code,
                :year,
                :months,
                :grade_id,
                :classroom_id,
                :sort_by

  validates :year, presence: true, numericality: { only_integer: true, greater_than: 2000 }
  validate :unity_must_be_informed
  validate :months_must_be_present_and_valid
  validate :unity_must_exist
  validate :unity_must_have_api_code
  validate :sort_by_must_be_valid
  validate :grade_must_belong_to_unity
  validate :classroom_must_belong_to_unity
  validate :classroom_must_belong_to_grade
  validate :must_have_rows

  def rows
    @rows ||= MonthlyAbsenceByStudentFetcher.call(
      unity_api_code: resolved_unity_api_code,
      year: parsed_year,
      months: parsed_months,
      grade_id: grade_id,
      classroom_id: classroom_id,
      sort_by: normalized_sort_by
    )
  end

  def parsed_months
    @parsed_months ||= Array(months).flat_map { |value| value.to_s.split(',') }
                                    .map(&:strip)
                                    .reject(&:blank?)
                                    .map(&:to_i)
                                    .uniq
                                    .sort
  end

  def parsed_year
    year.to_i
  end

  def normalized_sort_by
    value = sort_by.to_s
    return MonthlyAbsenceReportSortOrders::ABSENCES_COUNT if value.in?(%w[absences_count faltas])

    MonthlyAbsenceReportSortOrders::STUDENT_NAME
  end

  def unity
    @unity ||= if unity_id.present?
                 Unity.find_by(id: unity_id)
               elsif unity_api_code.present?
                 Unity.find_by(api_code: unity_api_code.to_s)
               end
  end

  def resolved_unity_api_code
    unity&.api_code || unity_api_code.to_s.presence
  end

  def filename
    "faltas_mensais_#{resolved_unity_api_code}_#{parsed_year}.pdf"
  end

  def month_label(month)
    I18n.l(Date.new(parsed_year, month, 1), format: '%B').upcase
  end

  private

  def unity_must_be_informed
    return if unity_id.present? || unity_api_code.present?

    errors.add(:unity_id, :blank)
  end

  def months_must_be_present_and_valid
    if parsed_months.empty?
      errors.add(:months, :blank)
      return
    end

    invalid = parsed_months.reject { |month| month.between?(1, 12) }
    return if invalid.empty?

    errors.add(:months, "contém valores inválidos: #{invalid.join(', ')}")
  end

  def unity_must_exist
    return if unity_id.blank? && unity_api_code.blank?
    return if unity.present?

    if unity_id.present?
      errors.add(:unity_id, 'escola não encontrada')
    else
      errors.add(:unity_api_code, 'escola não encontrada')
    end
  end

  def unity_must_have_api_code
    return if unity.blank?
    return if resolved_unity_api_code.present?

    errors.add(:unity_id, 'escola sem código de integração com o i-educar')
  end

  def sort_by_must_be_valid
    return if sort_by.blank?

    allowed = MonthlyAbsenceReportSortOrders.list + %w[faltas nome]
    return if sort_by.to_s.in?(allowed)

    errors.add(:sort_by, :invalid)
  end

  def grade_must_belong_to_unity
    return if grade_id.blank? || unity.blank?

    return if Grade.by_unity(unity.id).by_year(parsed_year).where(id: grade_id).exists?

    errors.add(:grade_id, 'não pertence à escola informada')
  end

  def classroom_must_belong_to_unity
    return if classroom_id.blank? || unity.blank?

    return if Classroom.by_unity(unity.id).by_year(parsed_year).where(id: classroom_id).exists?

    errors.add(:classroom_id, 'não pertence à escola informada')
  end

  def classroom_must_belong_to_grade
    return if classroom_id.blank? || grade_id.blank?

    return if Classroom.by_grade(grade_id).where(id: classroom_id).exists?

    errors.add(:classroom_id, 'não pertence à série informada')
  end

  def must_have_rows
    return if errors.present?
    return if resolved_unity_api_code.blank?

    errors.add(:base, 'nenhum registro de falta encontrado para os filtros informados') if rows.empty?
  end
end
