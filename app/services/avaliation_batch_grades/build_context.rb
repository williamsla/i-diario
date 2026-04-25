# frozen_string_literal: true

module AvaliationBatchGrades
  # Monta dados para a tela de lançamento em lote (etapa + turma + disciplina).
  class BuildContext
    MAX_ARITHMETIC_COLUMNS = 5

    attr_reader :classroom, :discipline, :step, :test_setting, :recorded_at, :assessments_count, :errors

    def initialize(classroom:, discipline:, step:, test_setting:, recorded_at:, assessments_count: nil,
                   teacher_calculation: nil, column_labels: nil)
      @classroom = classroom
      @discipline = discipline
      @step = step
      @test_setting = test_setting
      @recorded_at = recorded_at
      @assessments_count = assessments_count
      @teacher_calculation = teacher_calculation.presence || 'arithmetic'
      @column_labels = Array(column_labels)
      @errors = []
    end

    def supported?
      @errors = []
      return add_error(I18n.t('avaliations.batch.unsupported_test_setting')) if test_setting.blank?
      if batch_mode == :instrument_sum && test_setting.tests.empty?
        return add_error(I18n.t('avaliations.batch.sum_without_tests'))
      end

      true
    end

    def columns
      return [] unless supported?

      case batch_mode
      when :instrument_sum
        sum_columns
      when :weighted_sum
        weighted_sum_columns
      else
        arithmetic_columns
      end
    end

    def to_h
      return {} unless supported?

      min_count = minimum_reducible_assessments_count
      {
        mode: batch_mode,
        weighted_sum_mode: batch_mode == :weighted_sum,
        show_calculation_type_select: false,
        free_columns_mode: free_columns_mode?,
        minimum_assessments_count: min_count,
        teacher_calculation: @teacher_calculation.to_s,
        selected_max_score: selected_max_score_value,
        average_badge_label: average_badge_text,
        columns: columns,
        students: students_payload,
        test_setting: {
          minimum_score: test_setting.minimum_score,
          maximum_score: test_setting.maximum_score,
          average_calculation_type: test_setting.average_calculation_type,
          number_of_decimal_places: test_setting.number_of_decimal_places
        },
        recorded_at: recorded_at,
        step_id: step.id,
        step_label: step.to_s,
        classroom_label: classroom.description,
        unity_label: classroom.unity.to_s,
        discipline_label: discipline.to_s,
        year: classroom.year
      }
    end

    private

    def average_badge_text
      if %i[instrument_sum weighted_sum].include?(batch_mode)
        I18n.t('avaliations.batch.badge_sum')
      else
        I18n.t('avaliations.batch.badge_arithmetic')
      end
    end

    def selected_max_score_value
      test_setting.maximum_score.to_f
    end

    def add_error(msg)
      @errors << msg
      false
    end

    def batch_mode
      Mode.batch_mode(test_setting, @teacher_calculation)
    end

    def sum_columns
      test_setting.tests.order(:id).map.with_index do |tst, idx|
        av = avaliations_in_step.find_by(test_setting_test_id: tst.id)
        {
          index: idx,
          label: tst.description,
          editable_label: false,
          avaliation_id: av&.id,
          test_setting_test_id: tst.id,
          total_columns: test_setting.tests.size
        }
      end
    end

    def weighted_sum_columns
      count = resolved_free_column_count
      default_each = BigDecimal('10')
      pool = free_avaliations_ordered.dup

      (1..count).map do |n|
        canonical = I18n.t('avaliations.batch.short_assessment', n: n)
        av = avaliations_in_step.find_by(description: canonical)
        if av
          pool.delete(av)
        else
          av = pool.shift
        end
        label = label_for_column(n - 1, av&.description.presence || canonical)
        w = av&.weight.present? ? av.weight.to_f : default_each.to_f
        {
          index: n - 1,
          label: label,
          editable_label: true,
          avaliation_id: av&.id,
          test_setting_test_id: nil,
          total_columns: count,
          weight: w
        }
      end
    end

    def arithmetic_columns
      count = resolved_free_column_count
      pool = free_avaliations_ordered.dup

      (1..count).map do |n|
        canonical = I18n.t('avaliations.batch.arithmetic_description', n: n)
        av = avaliations_in_step.find_by(description: canonical)
        if av
          pool.delete(av)
        else
          av = pool.shift
        end
        label = label_for_column(n - 1, av&.description.presence || canonical)
        {
          index: n - 1,
          label: label,
          editable_label: true,
          avaliation_id: av&.id,
          test_setting_test_id: nil,
          total_columns: count
        }
      end
    end

    def resolved_free_column_count
      raw = assessments_count.presence&.to_i
      raw = existing_free_columns_count if raw.blank? || raw < 1
      raw = [raw, minimum_reducible_assessments_count].max
      [[raw, 1].max, MAX_ARITHMETIC_COLUMNS].min
    end

    def existing_free_columns_count
      arith = (1..MAX_ARITHMETIC_COLUMNS).count do |i|
        avaliations_in_step.exists?(description: I18n.t('avaliations.batch.arithmetic_description', n: i))
      end
      wsum = (1..MAX_ARITHMETIC_COLUMNS).count do |i|
        avaliations_in_step.exists?(description: I18n.t('avaliations.batch.short_assessment', n: i))
      end
      free_n = free_avaliations_ordered.size
      m = [arith, wsum, free_n].max
      m.positive? ? m : 1
    end

    def avaliations_in_step
      Avaliation
        .by_classroom_id(classroom.id)
        .by_discipline_id(discipline.id)
        .by_test_date_between(step.start_at, step.end_at)
    end

    # Avaliações “livres” (sem instrumento da config somatória) na etapa, na ordem do lançamento.
    def free_avaliations_ordered
      @free_avaliations_ordered ||= avaliations_in_step
        .where(test_setting_test_id: nil)
        .order(:test_date, :id)
        .to_a
    end

    def free_columns_mode?
      batch_mode != :instrument_sum
    end

    # Só permite reduzir até a última coluna que já possui alguma nota lançada.
    def minimum_reducible_assessments_count
      return 1 unless free_columns_mode?

      free_cols = free_avaliations_ordered
      return 1 if free_cols.blank?

      last_with_notes = -1
      free_cols.each_with_index do |av, idx|
        has_any_note = DailyNoteStudent
          .joins(:daily_note)
          .where(daily_notes: { avaliation_id: av.id })
          .where.not(note: nil)
          .exists?
        last_with_notes = idx if has_any_note
      end

      [last_with_notes + 1, 1].max
    end

    def label_for_column(index, fallback)
      raw = @column_labels[index].to_s.strip
      raw.present? ? raw : fallback
    end

    def students_payload
      grade_ids = numeric_grade_ids
      return [] if grade_ids.blank?

      enrollments = StudentEnrollmentsRetriever.call(
        classrooms: classroom,
        grades: grade_ids,
        disciplines: discipline,
        date: recorded_at,
        score_type: StudentEnrollmentScoreTypeFilters::NUMERIC,
        search_type: :by_date
      )
      return [] if enrollments.blank?

      cols = columns
      enrollments.map do |enrollment|
        student = enrollment.student
        notes = cols.map { |col| note_for(student.id, col) }
        row = {
          id: student.id,
          name: student.name,
          notes: notes,
          average: preview_average(student.id, cols),
          total_points: preview_weighted_total(student.id, cols)
        }
        if batch_mode == :weighted_sum
          row[:normalized_average] = preview_weighted_normalized_average(student.id, cols)
        end
        row
      end
    end

    def note_for(student_id, col)
      return nil if col[:avaliation_id].blank?

      dn = DailyNote.find_by(avaliation_id: col[:avaliation_id])
      return nil if dn.blank?

      dns = dn.students.find_by(student_id: student_id)
      dns&.note
    end

    def preview_average(student_id, cols)
      if batch_mode == :instrument_sum
        # Mesma regra de StudentAverageCalculator (sum): soma das notas ÷ default_division_weight.
        # Com "Gerar média das avaliações?" desmarcado o formulário grava peso 1 → exibe só o somatório.
        sum = sum_of_entered_notes(student_id, cols)
        return nil if sum.blank?

        divisor = test_setting.default_division_weight.to_i
        divisor = 1 if divisor < 1
        (sum / divisor.to_d).round(batch_preview_decimal_places)
      else
        values = cols.map { |col| note_for(student_id, col) }.compact.map(&:to_f)
        return nil if values.empty?

        (values.sum / values.size).round(batch_preview_decimal_places)
      end
    end

    def preview_weighted_total(student_id, cols)
      s = sum_of_entered_notes(student_id, cols)
      s ? s.round(batch_preview_decimal_places) : nil
    end

    def sum_of_entered_notes(student_id, cols)
      total = 0.to_d
      any = false
      cols.each do |col|
        n = note_for(student_id, col)
        next if n.blank?

        any = true
        total += n.to_d
      end
      any ? total : nil
    end

    def batch_preview_decimal_places
      d = test_setting.number_of_decimal_places.to_i
      d = 2 if d.negative?
      d
    end

    # Média na escala 0..10 para somatório com pesos livres (colunas com :weight).
    def preview_weighted_normalized_average(student_id, cols)
      return nil unless batch_mode == :weighted_sum

      total = preview_weighted_total(student_id, cols)
      return nil if total.blank?

      weight_sum = cols.sum { |c| (c[:weight].presence || 0).to_d }
      return nil if weight_sum <= 0

      # Primeiro normaliza para a nota máxima configurada e depois converte para escala 0..10.
      average_on_setting_scale = total.to_d / (weight_sum / test_setting.maximum_score.to_d)
      (average_on_setting_scale * (10.to_d / test_setting.maximum_score.to_d)).round(2)
    end

    def numeric_grade_ids
      @numeric_grade_ids ||= begin
        cgs = classroom.classrooms_grades.select do |cg|
          er = cg.exam_rule
          next false if er.blank?

          [ScoreTypes::NUMERIC, ScoreTypes::NUMERIC_AND_CONCEPT].include?(er.score_type)
        end
        cgs.map(&:grade_id).uniq
      end
    end
  end
end
