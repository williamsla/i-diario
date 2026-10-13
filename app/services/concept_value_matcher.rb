# frozen_string_literal: true

# A tabela conceitual guarda o teto numérico de cada conceito (valor_maximo).
# O lançamento grava esse número em decimal. BigDecimal#to_s muda com a escala
# ("0.1e2", "10.0", "10.00"), então comparar por string deixa o select em branco
# e o relatório mostra o número cru em vez da sigla.
class ConceptValueMatcher
  NUMERIC_PATTERN = /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/

  def self.canonical(value)
    decimal = to_decimal(value)
    return if decimal.nil?

    formatted = decimal.to_s('F')
    return formatted unless formatted.include?('.')

    formatted.sub(/0+\z/, '').sub(/\.\z/, '')
  end

  def self.option_id(rounding_table, value)
    matched = find(rounding_table, value)
    canonical(matched ? matched.value : value)
  end

  def self.display(rounding_table, value)
    return if value.nil?

    found = find(rounding_table, value)
    return found.label.to_s.presence || found.to_s if found

    canonical(value)
  end

  def self.find(rounding_table, value)
    return if rounding_table.blank?

    decimal = to_decimal(value)
    return if decimal.nil?

    rows = Array(rounding_table.rounding_table_values)
    return if rows.empty?

    exact = rows.find { |row| to_decimal(row.value) == decimal }
    return exact if exact

    # Mesma regra do i-Educar: menor valor máximo que ainda cobre a nota.
    rows
      .select { |row| ceiling_covers?(row, decimal) }
      .min_by { |row| to_decimal(row.value) }
  end

  def self.ceiling_covers?(row, decimal)
    ceiling = to_decimal(row.value)
    !ceiling.nil? && ceiling >= decimal
  end

  def self.to_decimal(value)
    return value if value.is_a?(BigDecimal)
    return if value.nil?

    string = value.to_s.strip
    return if string.empty? || string !~ NUMERIC_PATTERN

    BigDecimal(string)
  rescue ArgumentError
    nil
  end
  private_class_method :to_decimal, :ceiling_covers?
end
