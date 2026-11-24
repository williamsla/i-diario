# frozen_string_literal: true

# Classifica cada etapa da tela de avaliações numéricas:
# - not_started: nenhuma avaliação da etapa foi preenchida
# - partial: há nota lançada, mas ainda falta avaliação ou aluno
# - complete: toda avaliação esperada está completa
#
# No somatório, o esperado são os instrumentos da configuração.
# Na média aritmética ou no somatório com pesos, o esperado são as
# avaliações já criadas na etapa — a quantidade é escolhida no lançamento.
class AvaliationStepFillStatus
  NOT_STARTED = 'not_started'
  PARTIAL = 'partial'
  COMPLETE = 'complete'

  Status = Struct.new(:key, :complete_count, :total_count) do
    def label_class
      case key
      when AvaliationStepFillStatus::COMPLETE then 'label-success'
      when AvaliationStepFillStatus::PARTIAL then 'label-warning'
      else 'label-default'
      end
    end
  end

  def initialize(classroom:, discipline:, steps:)
    @classroom = classroom
    @discipline = discipline
    @steps = Array(steps)
  end

  def by_step_id
    steps.each_with_object({}) do |step, acc|
      acc[step.id] = self.class.for_step(
        avaliations: avaliations_in(step),
        instrument_test_ids: instrument_test_ids_for(step),
        complete_ids: complete_avaliation_ids,
        noted_ids: avaliation_ids_with_note
      )
    end
  end

  def self.for_step(avaliations:, instrument_test_ids:, complete_ids:, noted_ids:)
    complete_ids = complete_ids.to_set
    noted_ids = noted_ids.to_set
    columns = groups_for(avaliations, instrument_test_ids).map do |group|
      column_state(group, complete_ids, noted_ids)
    end
    classify(columns)
  end

  def self.classify(columns)
    total = columns.size
    complete_count = columns.count { |column| column[:complete] }
    started = columns.any? { |column| column[:started] }

    key = if total.zero? || !started
            NOT_STARTED
          elsif complete_count == total
            COMPLETE
          else
            PARTIAL
          end

    Status.new(key, complete_count, total)
  end

  def self.groups_for(avaliations, instrument_test_ids)
    ids = Array(instrument_test_ids)
    return avaliations.map { |avaliation| [avaliation] } if ids.blank?

    ids.map { |test_id| avaliations.select { |avaliation| avaliation.test_setting_test_id == test_id } }
  end

  def self.column_state(group, complete_ids, noted_ids)
    complete = group.any? { |avaliation| complete_ids.include?(avaliation.id) }
    started = complete || group.any? { |avaliation| noted_ids.include?(avaliation.id) }
    { complete: complete, started: started }
  end

  private_class_method :groups_for, :column_state

  private

  attr_reader :classroom, :discipline, :steps

  def avaliations_in(step)
    start_on = step.start_at.to_date
    end_on = step.end_at.to_date
    all_avaliations.select do |avaliation|
      date = avaliation.test_date
      date.present? && (start_on..end_on).cover?(date.to_date)
    end
  end

  def all_avaliations
    @all_avaliations ||= begin
      if steps.blank?
        []
      else
        Avaliation
          .by_classroom_id(classroom.id)
          .by_discipline_id(discipline.id)
          .by_test_date_between(range_start, range_end)
          .select(:id, :test_date, :test_setting_test_id)
          .to_a
      end
    end
  end

  def range_start
    steps.map { |step| step.start_at.to_date }.min
  end

  def range_end
    steps.map { |step| step.end_at.to_date }.max
  end

  def instrument_test_ids_for(step)
    setting = test_setting_for(step)
    return [] unless setting&.sum_calculation_type?

    @instrument_test_ids_by_setting ||= {}
    @instrument_test_ids_by_setting[setting.id] ||= setting.tests.order(:id).pluck(:id)
  end

  def test_setting_for(step)
    @test_setting_by_step ||= {}
    return @test_setting_by_step[step.id] if @test_setting_by_step.key?(step.id)

    @test_setting_by_step[step.id] = TestSettingFetcher.current(classroom, step, discipline: discipline)
  end

  def complete_avaliation_ids
    @complete_avaliation_ids ||= begin
      ids = all_avaliations.map(&:id)
      if ids.blank?
        Set.new
      else
        rows = DailyNote
               .where(avaliation_id: ids)
               .joins(:daily_note_status)
               .pluck(:avaliation_id, 'daily_note_statuses.status')
        rows.group_by(&:first).each_with_object(Set.new) do |(avaliation_id, pairs), complete|
          statuses = pairs.map(&:last)
          complete << avaliation_id if statuses.all? { |status| status == DailyNoteStatuses::COMPLETE }
        end
      end
    end
  end

  def avaliation_ids_with_note
    @avaliation_ids_with_note ||= begin
      ids = all_avaliations.map(&:id)
      if ids.blank?
        Set.new
      else
        DailyNoteStudent
          .active
          .joins(:daily_note)
          .where(daily_notes: { avaliation_id: ids })
          .where.not(note: nil)
          .distinct
          .pluck('daily_notes.avaliation_id')
          .to_set
      end
    end
  end
end
