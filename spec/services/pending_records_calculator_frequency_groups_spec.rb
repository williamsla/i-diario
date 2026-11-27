require 'rails_helper'

RSpec.describe PendingRecordsCalculator, type: :service do
  let(:exam_rule) { create(:exam_rule, frequency_type: FrequencyTypes::GENERAL) }
  let(:classroom) { create(:classroom, year: Date.current.year) }
  let!(:classrooms_grade) { create(:classrooms_grade, classroom: classroom, exam_rule: exam_rule) }
  let(:teacher) { create(:teacher) }
  let(:general_discipline) { create(:discipline, description: 'Arte') }
  let(:specific_discipline) { create(:discipline, description: 'Estudo dirigido de Matemática') }
  let(:calculator) { described_class.new(school_year: classroom.year) }

  before do
    create(
      :teacher_discipline_classroom,
      teacher: teacher,
      classroom: classroom,
      discipline: general_discipline,
      grade: classrooms_grade.grade,
      year: classroom.year,
      allow_absence_by_discipline: 0,
      active: true
    )
    create(
      :teacher_discipline_classroom,
      teacher: teacher,
      classroom: classroom,
      discipline: specific_discipline,
      grade: classrooms_grade.grade,
      year: classroom.year,
      allow_absence_by_discipline: 1,
      active: true
    )
  end

  describe '#general_frequency_discipline?' do
    it 'trata cada vínculo à parte quando a turma mistura frequência geral e por dia' do
      expect(
        calculator.send(:general_frequency_discipline?, classroom, teacher.id, general_discipline.id)
      ).to eq(true)
      expect(
        calculator.send(:general_frequency_discipline?, classroom, teacher.id, specific_discipline.id)
      ).to eq(false)
    end

    it 'mantém todas as disciplinas por dia quando a regra de avaliação é por disciplina' do
      exam_rule.update!(frequency_type: FrequencyTypes::BY_DISCIPLINE)

      expect(
        calculator.send(:general_frequency_discipline?, classroom, teacher.id, general_discipline.id)
      ).to eq(false)
      expect(
        calculator.send(:general_frequency_discipline?, classroom, teacher.id, specific_discipline.id)
      ).to eq(false)
    end
  end

  describe 'conteúdo do mesmo turno' do
    let(:monday) { Date.new(2026, 3, 2) }

    it 'não usa o conteúdo de outro professor quando o turno é integral' do
      dates = calculator.send(
        :content_dates_for_teachers,
        { 10 => Set.new([monday]), 20 => Set.new },
        [20]
      )

      expect(dates).not_to include(monday)
    end

    it 'usa o conteúdo de outro professor do mesmo turno' do
      dates = calculator.send(
        :content_dates_for_teachers,
        { 10 => Set.new([monday]), 20 => Set.new },
        [10, 20]
      )

      expect(dates).to include(monday)
    end
  end

  describe '#build_shared_general_pending_frequency' do
    let(:monday) { Date.current.beginning_of_week(:monday) }
    let(:next_monday) { monday + 7.days }
    let(:today) { next_monday }

    before do
      allow(calculator).to receive(:get_equivalent_weekday_number) { |date| date.wday }
      allow(calculator).to receive(:filter_saturdays_by_events) { |dates, _classroom, _calendar| dates }
      allow(calculator).to receive(:apply_optional_holidays!).and_return(Set.new)
      allow(calculator).to receive(:lessons_board_archive_date).and_return(nil)
      allow(TeacherAbsence).to receive(:absence_dates_for).and_return(Set.new)
      allow(TeacherAbsence).to receive(:make_up_dates_for).and_return(Set.new)
    end

    def shared_dates(general_freq_dates: Set.new, general_freq_periods: nil)
      calculator.send(
        :build_shared_general_pending_frequency,
        classroom: classroom,
        teacher: teacher,
        discipline: general_discipline,
        teacher_weekdays: ['monday'],
        discarded_weekday_names: [],
        all_school_days: [monday, next_monday, monday + 1.day],
        general_freq_dates: general_freq_dates,
        general_freq_periods: general_freq_periods,
        general_discipline_ids: [general_discipline.id],
        start_date: monday,
        end_date: today,
        today: today,
        school_calendar: nil
      )[:dates]
    end

    it 'repete a mesma lista de dias de aula ainda sem frequência geral' do
      expect(shared_dates).to eq([monday, next_monday])
    end

    it 'tira da lista o dia que já tem frequência geral' do
      expect(shared_dates(general_freq_dates: Set.new([monday]))).to eq([next_monday])
    end

    it 'mantém o dia pendente quando a frequência gravada é de outro turno' do
      allow(calculator).to receive(:teacher_frequency_periods).and_return(by_weekday: { 1 => [2] }, fallback: [2])

      expect(
        shared_dates(general_freq_dates: Set.new([monday]), general_freq_periods: { monday => [1] })
      ).to eq([monday, next_monday])
    end
  end
end
