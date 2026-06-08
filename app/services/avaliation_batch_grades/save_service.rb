# frozen_string_literal: true

module AvaliationBatchGrades
  # Cria/atualiza avaliações da etapa, diários de avaliação e notas por aluno em transação.
  class SaveService
    include StudentEnrollmentsForStep

    attr_reader :errors, :classroom, :discipline, :step

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
      av = scoped_avaliation_for_step(find_scoped_avaliation(col[:avaliation_id]))
      av ||= scoped_avaliation_for_step(avaliations_scope.find_by(description: desc))
      av ||= scoped_avaliation_for_step(avaliations_scope.find_by(description: canonical))
      av ||= Avaliation.new(
        classroom: @classroom,
        discipline: @discipline,
        school_calendar: @school_calendar,
        test_setting: @test_setting,
        test_date: @recorded_at,
        description: desc,
        teacher_id: @teacher.id
      )
      apply_batch_attributes!(av)
      av.test_date = @recorded_at
      av.description = desc
      assign_grade_ids!(av)
      apply_equal_arithmetic_weights!(av, col)
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
      av = scoped_avaliation_for_step(find_scoped_avaliation(col[:avaliation_id]))
      av ||= scoped_avaliation_for_step(avaliations_scope.find_by(description: desc))
      av ||= scoped_avaliation_for_step(avaliations_scope.find_by(description: canonical))
      av ||= Avaliation.new(
        classroom: @classroom,
        discipline: @discipline,
        school_calendar: @school_calendar,
        test_setting: @test_setting,
        test_date: @recorded_at,
        description: desc,
        teacher_id: @teacher.id
      )
      apply_batch_attributes!(av)
      av.test_date = @recorded_at
      av.description = desc
      av.weight = @resolved_weights[col[:index]]
      assign_grade_ids!(av)
      av.save!
      av
    end

    def resolve_sum_avaliation!(col)
      tst = TestSettingTest.find(col[:test_setting_test_id])
      av = pick_canonical_instrument_avaliation(col, tst)
      av ||= build_new_sum_avaliation(tst)
      consolidate_duplicate_instrument_avaliations!(tst.id, keep: av)
      apply_batch_attributes!(av)
      av.test_date = @recorded_at
      assign_grade_ids!(av)
      av.save!
      av
    end

    def build_new_sum_avaliation(tst)
      Avaliation.new(
        classroom: @classroom,
        discipline: @discipline,
        school_calendar: @school_calendar,
        test_setting: @test_setting,
        test_setting_test: tst,
        test_date: @recorded_at,
        weight: tst.weight,
        teacher_id: @teacher.id
      )
    end

    # Escolhe uma avaliação por instrumento quando há duplicatas na etapa (causa comum do erro de unicidade).
    def pick_canonical_instrument_avaliation(col, tst)
      scoped_avaliation_for_step(find_scoped_avaliation(col[:avaliation_id])) ||
        pick_best_from_instrument_pool(instrument_pool_for_step(tst.id), col[:avaliation_id])
    end

    def scoped_avaliation_for_step(avaliation)
      return if avaliation.blank?
      return unless avaliation.test_date.between?(@step.start_at, @step.end_at)

      avaliation
    end

    def instrument_pool_for_step(test_setting_test_id)
      # Só avaliações da etapa atual. Reutilizar instrumento de outra etapa move test_date
      # e sobrescreve o diário/notas já lançados na etapa de origem.
      instrument_avaliations_scope
        .where(test_setting_test_id: test_setting_test_id)
        .merge(avaliations_scope)
        .order(:id)
        .to_a
    end

    def pick_best_from_instrument_pool(pool, preferred_id)
      return if pool.blank?

      if preferred_id.present?
        found = pool.find { |a| a.id == preferred_id.to_i }
        return found if found
      end

      with_notes = pool.select { |a| avaliation_has_notes?(a) }
      (with_notes.presence || pool).min_by(&:id)
    end

    def consolidate_duplicate_instrument_avaliations!(test_setting_test_id, keep:)
      duplicate_instrument_avaliations_in_step(test_setting_test_id, keep: keep).each do |extra|
        merge_notes_into_avaliation!(keep, extra)
        destroy_duplicate_avaliation!(extra)
      end
    end

    def duplicate_instrument_avaliations_in_step(test_setting_test_id, keep:)
      scope = instrument_avaliations_scope
        .where(test_setting_test_id: test_setting_test_id)
        .merge(avaliations_scope)
      scope = scope.where.not(id: keep.id) if keep.persisted?
      scope.order(:id).to_a
    end

    def merge_notes_into_avaliation!(keep, source)
      source_dn = DailyNote.find_by(avaliation_id: source.id)
      return if source_dn.blank?

      keep_dn = DailyNoteCreator.new(avaliation_id: keep.id).find_or_create
      return unless keep_dn.persisted?

      source_dn.students.where.not(note: nil).find_each do |dns|
        keep_dns = find_or_initialize_daily_note_student(keep_dn, dns.student_id)
        keep_dns.note = dns.note if keep_dns.note.nil?
        keep_dns.active = true
        keep_dns.save!
      end
    end

    def destroy_duplicate_avaliation!(avaliation)
      svc = DestroyColumnService.new(avaliation: avaliation)
      return if svc.call

      avaliation.errors.add(
        :base,
        svc.error.presence || I18n.t('avaliations.batch.duplicate_destroy_failed')
      )
      raise ActiveRecord::RecordInvalid, avaliation
    end

    def avaliation_has_notes?(avaliation)
      DailyNoteStudent
        .joins(:daily_note)
        .where(daily_notes: { avaliation_id: avaliation.id })
        .where.not(note: nil)
        .exists?
    end

    def apply_batch_attributes!(av)
      av.test_setting = @test_setting
      av.school_calendar = @school_calendar
      av.calendar_step = @step
      av.teacher_id = @teacher.id
      av.current_user = @current_user
    end

    def find_scoped_avaliation(id)
      return if id.blank?

      avaliations_scope.find_by(id: id)
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

      @notes_params.each do |student_id_str, notes_array|
        sid = student_id_str.to_i
        next if sid.zero?

        arr = Array(notes_array)
        raw = arr[column_index]

        dns = find_or_initialize_daily_note_student(daily_note, sid)
        dns.active = student_active_in_step_by_student_id?(sid)
        dns.note = parse_note(raw)
        dns.save!
      end
    end

    def find_or_initialize_daily_note_student(daily_note, student_id)
      DailyNoteStudent
        .with_discarded
        .find_or_initialize_by(daily_note_id: daily_note.id, student_id: student_id)
        .tap do |dns|
          dns.undiscard if dns.persisted? && dns.discarded?
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
