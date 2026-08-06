# frozen_string_literal: true

module EducaMais
  class BnccSkillsQuery
    GRADE_ENUMS = [
      ElementaryEducations,
      ChildEducations,
      AdultAndYouthEducations,
      GroupChildEducations
    ].freeze

    MIN_QUERY_LENGTH = 2

    def self.call(scope: LearningObjectivesAndSkill.all, q: nil, serie: nil, disciplina: nil, limit: 50)
      new(scope, q, serie, disciplina, limit).call
    end

    def initialize(scope, q, serie, disciplina, limit)
      @scope = scope
      @q = q
      @serie = serie
      @disciplina = disciplina
      @limit = limit.to_i.positive? ? [limit.to_i, 100].min : 50
    end

    def call
      term = @q.to_s.strip
      rel = @scope.ordered

      if term.present?
        return rel.none if term.length < MIN_QUERY_LENGTH

        return apply_text_search(rel, term).limit(@limit)
      end

      rel = apply_serie(rel) if @serie.present?
      rel = apply_disciplina(rel) if @disciplina.present?
      rel.limit(@limit)
    end

    private

    def apply_text_search(rel, term)
      rel.where(
        'unaccent(code) ILIKE unaccent(:t) OR unaccent(description) ILIKE unaccent(:t)',
        t: "%#{term}%"
      )
    end

    def apply_serie(rel)
      keys = grade_keys_for_serie(@serie)
      return rel if keys.empty?

      rel.where('grades && ARRAY[?]::varchar[]', keys)
    end

    def apply_disciplina(rel)
      keys = discipline_keys_for_label(@disciplina)
      return rel if keys.empty?

      rel.where(discipline: keys)
    end

    def normalize(str)
      str.to_s.downcase.gsub(/[º°ª]/, 'o').gsub(/\s+/, ' ').strip
    end

    def grade_keys_for_serie(serie)
      n_serie = normalize(serie)
      digits = serie.to_s.scan(/\d+/).join

      GRADE_ENUMS.flat_map do |enum|
        enum.list.select do |key|
          label = enum.t(key)
          n_label = normalize(label)
          n_label == n_serie ||
            n_serie.include?(n_label) ||
            n_label.include?(n_serie) ||
            (digits.present? && label.to_s.match?(/\b#{Regexp.escape(digits)}\b/))
        end
      end.uniq
    end

    def discipline_keys_for_label(label)
      n = normalize(label)
      BnccDisciplines.list.select do |key|
        d = normalize(BnccDisciplines.t(key))
        d == n || d.include?(n) || n.include?(d)
      end
    end
  end
end
