# frozen_string_literal: true

module AvaliationBatchGrades
  # Cria/atualiza avaliações da etapa, diários de avaliação e notas por aluno em transação.
  class SaveService
    attr_reader :errors

    def initialize(classroom:, discipline:, step:, teacher:, current_user:, school_calendar:,
                   test_setting:, recorded_at:, assessments_count:, notes_params:,
                   teacher_calculation: nil, column_weights: nil, column_labels: nil)
      @classroom = classroom
      @discipline = discipline
      @step = step
      @teacher = teacher
      @current_user = current_user
      @school_calendar = school_calendar
      @test_setting = test_setting
      @recorded_at = recorded_at.to_date
      @assessments_count = assessments_count
      @teacher_calculation = teacher_calculation.presence || 'arithmetic'
      @column_weights = normalize_column_weights(column_weights)
      @column_labels = normalize_column_labels(column_labels)
      @notes_params = normalize_notes(notes_params)
      @errors = []
      @resolved_weights = nil
    end

    def call
      ctx = BuildContext.new(
        classroom: @classroom,
        discipline: @discipline,
        step: @step,
        test_setting: @test_setting,
        recorded_at: @recorded_at,
        assessments_count: @assessments_count,
        teacher_calculation: @teacher_calculation,
        column_labels: @column_labels
      )
      unless ctx.supported?
        @errors.concat(ctx.errors)
        return false
      end

      if batch_mode == :weighted_sum
        @resolved_weights = compiled_weights_for_context(ctx)
      end

      ActiveRecord::Base.transaction do
        ctx.columns.each_with_index do |col, column_index|
          avaliation = resolve_avaliation!(col)
          ensure_daily_note!(avaliation)
          save_notes_for_column!(avaliation, column_index)
        end
      end
      true
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.record.errors.full_messages.join(', ')
      false
    rescue StandardError => e
      Rails.logger.error(
        "[AvaliationBatchGrades::SaveService] #{e.class}: #{e.message}\n#{Array(e.backtrace).join("\n")}"
      )
      @errors << I18n.t('avaliations.batch.unexpected_error')
      false
    end

    private

    def normalize_column_weights(raw)
      return [] if raw.blank?

      arr = if raw.is_a?(Array)
        raw
      elsif raw.is_a?(ActionController::Parameters)
        raw.permit!.to_h.sort_by { |k, _| k.to_i }.map(&:last)
      elsif raw.respond_to?(:to_unsafe_h)
        raw.to_unsafe_h.sort_by { |k, _| k.to_i }.map(&:last)
      elsif raw.is_a?(Hash)
        raw.sort_by { |k, _| k.to_i }.map(&:last)
      else
        []
      end
      arr.map { |v| parse_weight_value(v) }.compact
    end

    def parse_weight_value(val)
      return nil if val.blank?

      BigDecimal(val.to_s.tr(',', '.').strip)
    rescue ArgumentError
      nil
    end

    def normalize_notes(raw)
      return {} if raw.blank?

      h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      h = h.to_unsafe_h if h.respond_to?(:to_unsafe_h)
      h = h.with_indifferent_access
      h.transform_values { |arr| Array(arr).map(&:presence) }
    end

    def normalize_column_labels(raw)
      return [] if raw.blank?

      arr = if raw.is_a?(Array)
        raw
      elsif raw.is_a?(ActionController::Parameters)
        raw.permit!.to_h.sort_by { |k, _| k.to_i }.map(&:last)
      elsif raw.respond_to?(:to_unsafe_h)
        raw.to_unsafe_h.sort_by { |k, _| k.to_i }.map(&:last)
      elsif raw.is_a?(Hash)
        raw.sort_by { |k, _| k.to_i }.map(&:last)
      else
        []
      end
      arr.map { |v| v.to_s.strip }
    end

    def batch_mode
      Mode.batch_mode(@test_setting, @teacher_calculation)
    end

    def batch_weight_param_set?(value)
      return false if value.nil?
      return true if value.is_a?(Numeric)
      value.present?
    end

    def max_total_score
      @test_setting.maximum_score.to_d
    end

    def compiled_weights_for_context(ctx)
      n = ctx.columns.size
      return [] if n.zero?

      default_each = (max_total_score / n).round(4)
      (0...n).map do |i|
        w = @column_weights[i] if @column_weights && i < @column_weights.size && batch_weight_param_set?(@column_weights[i])
        w ||= begin
          cw = ctx.columns[i][:weight]
          batch_weight_param_set?(cw) ? BigDecimal(cw.to_s) : nil
        end
        (w || default_each).round(4)
      end
    end

    def validate_weights_sum!(weights, ctx)
      return [true, nil] if weights.blank?

      s = weights.reduce(0.to_d, :+)
      max_t = max_total_score
      diff = (s - max_t).abs
      return [true, nil] if diff < BigDecimal('0.02')

      [
        false,
        I18n.t(
          'avaliations.batch.weights_sum_invalid',
          current: format('%.2f', s.to_f).tr('.', ','),
          expected: format('%.2f', max_t.to_f).tr('.', ',')
        )
      ]
    end

    def avaliations_scope
      Avaliation
        .by_classroom_id(@classroom.id)
        .by_discipline_id(@discipline.id)
        .by_test_date_between(@step.start_at, @step.end_at)
    end

    def instrument_avaliations_scope
      Avaliation
        .by_classroom_id(@classroom.id)
        .by_discipline_id(@discipline.id)
        .by_test_setting_instruments(@test_setting.id)
    end

    def resolve_avaliation!(col)
      case batch_mode
      when :instrument_sum
        resolve_sum_avaliation!(col)
      when :weighted_sum
        resolve_weighted_sum_avaliation!(col)
      else
        resolve_arithmetic_avaliation!(col)
      end
    end

    def resolve_arithmetic_avaliation!(col)
      canonical = I18n.t('avaliations.batch.arithmetic_description', n: col[:index] + 1)
      desc = col[:label].to_s.strip.presence || canonical
      av = find_scoped_avaliation(col[:avaliation_id])
      av ||= avaliations_scope.find_by(description: desc)
      av ||= avaliations_scope.find_by(description: canonical)
      av ||= Avaliation.new(
        classroom: @classroom,
        discipline: @discipline,
        school_calendar: @school_calendar,
        test_setting: @test_setting,
        test_date: @recorded_at,
        description: desc,
        teacher_id: @teacher.id
      )
      av.test_date = @recorded_at
      av.description = desc
      assign_grade_ids!(av)
      apply_equal_arithmetic_weights!(av, col)
      av.teacher_id = @teacher.id
      av.current_user = @current_user
      av.save!
      av
    end

    def apply_equal_arithmetic_weights!(av, col)
      return unless @test_setting.arithmetic_and_sum_calculation_type?

      n = col[:total_columns].to_i
      n = 1 if n < 1
      av.weight = (max_total_score / n).round(4)
    end

    def resolve_weighted_sum_avaliation!(col)
      canonical = I18n.t('avaliations.batch.short_assessment', n: col[:index] + 1)
      desc = col[:label].to_s.strip.presence || canonical
      av = find_scoped_avaliation(col[:avaliation_id])
      av ||= avaliations_scope.find_by(description: desc)
      av ||= avaliations_scope.find_by(description: canonical)
      av ||= Avaliation.new(
        classroom: @classroom,
        discipline: @discipline,
        school_calendar: @school_calendar,
        test_setting: @test_setting,
        test_date: @recorded_at,
        description: desc,
        teacher_id: @teacher.id
      )
      av.test_date = @recorded_at
      av.description = desc
      av.weight = @resolved_weights[col[:index]]
      assign_grade_ids!(av)
      av.teacher_id = @teacher.id
      av.current_user = @current_user
      av.save!
      av
    end

    def resolve_sum_avaliation!(col)
      tst = TestSettingTest.find(col[:test_setting_test_id])
      av = find_scoped_avaliation(col[:avaliation_id])
      av ||= instrument_avaliations_scope.find_by(test_setting_test_id: tst.id)
      av ||= avaliations_scope.find_by(test_setting_test_id: tst.id)
      av ||= Avaliation.new(
        classroom: @classroom,
        discipline: @discipline,
        school_calendar: @school_calendar,
        test_setting: @test_setting,
        test_setting_test: tst,
        test_date: @recorded_at,
        weight: tst.weight,
        teacher_id: @teacher.id
      )
      av.test_date = @recorded_at
      assign_grade_ids!(av)
      av.teacher_id = @teacher.id
      av.current_user = @current_user
      av.save!
      av
    end

    def find_scoped_avaliation(id)
      return if id.blank?

      Avaliation.find_by(id: id, classroom_id: @classroom.id, discipline_id: @discipline.id)
    end

    def assign_grade_ids!(av)
      ids = numeric_grade_ids
      raise I18n.t('avaliations.batch.no_numeric_grades') if ids.blank?

      av.grade_ids = ids
    end

    def numeric_grade_ids
      @classroom.classrooms_grades.select do |cg|
        er = cg.exam_rule
        er.present? && [ScoreTypes::NUMERIC, ScoreTypes::NUMERIC_AND_CONCEPT].include?(er.score_type)
      end.map(&:grade_id).uniq
    end

    def ensure_daily_note!(avaliation)
      DailyNoteCreator.new(avaliation_id: avaliation.id).find_or_create
    end

    def save_notes_for_column!(avaliation, column_index)
      creator = DailyNoteCreator.new(avaliation_id: avaliation.id)
      creator.find_or_create
      daily_note = creator.daily_note
      unless daily_note.persisted?
        raise ActiveRecord::RecordInvalid.new(daily_note)
      end

      ensure_students!(daily_note)

      @notes_params.each do |student_id_str, notes_array|
        sid = student_id_str.to_i
        next if sid.zero?

        arr = Array(notes_array)
        raw = arr[column_index]

        dns = daily_note.students.find_or_initialize_by(student_id: sid)
        dns.active = true if dns.new_record?
        dns.note = parse_note(raw)
        dns.save!
      end
    end

    def ensure_students!(daily_note)
      @notes_params.each_key do |student_id_str|
        sid = student_id_str.to_i
        next if sid.zero?

        next if daily_note.students.where(student_id: sid).exists?

        daily_note.students.create!(student_id: sid, active: true)
      end
    end

    def parse_note(val)
      return nil if val.blank?

      BigDecimal(val.to_s.tr(',', '.').strip)
    rescue ArgumentError
      nil
    end
  end
end
