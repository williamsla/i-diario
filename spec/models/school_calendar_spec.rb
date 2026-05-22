require 'rails_helper'

RSpec.describe SchoolCalendar, type: :model do
  describe 'attributes' do
    it { expect(subject).to respond_to(:year) }
    it { expect(subject).to respond_to(:number_of_classes) }
    it { expect(subject).to respond_to(:unity_id) }
  end

  describe 'associations' do
    it { expect(subject).to belong_to(:unity) }
    it { expect(subject).to have_many(:steps) }
    it { expect(subject).to have_many(:events) }
  end

  describe 'scopes' do
    describe '.by_school_day' do
      it 'should return the school calendars where the date informed is a valid school day' do
        school_calendar_one = build(:school_calendar, year: 2020)
        school_calendar_one.steps.build(
          start_at: '2020-02-15',
          end_at: '2020-05-01',
          start_date_for_posting: '2020-02-15',
          end_date_for_posting: '2020-05-01'
        )
        school_calendar_one.save!

        school_calendar_two = build(:school_calendar, year: 2021)
        school_calendar_two.steps.build(
          start_at: '2021-02-15',
          end_at: '2021-05-01',
          start_date_for_posting: '2021-02-15',
          end_date_for_posting: '2021-05-01'
        )
        school_calendar_two.save!

        school_calendar_three = build(:school_calendar, year: 2022)
        school_calendar_three.steps.build(
          start_at: '2022-02-15',
          end_at: '2022-05-01',
          start_date_for_posting: '2022-02-15',
          end_date_for_posting: '2022-05-01'
        )
        school_calendar_three.save!

        relation = SchoolCalendar.by_school_day('15/03/2021')

        expect(relation.exists?(school_calendar_one.id)).to be(false)
        expect(relation.exists?(school_calendar_two.id)).to be(true)
        expect(relation.exists?(school_calendar_three.id)).to be(false)
      end
    end
  end

  describe '#school_term_day?' do
    let(:school_calendar) { create(:school_calendar, year: 2026) }
    let(:school_term_type) { create(:school_term_type, steps_number: 2) }
    let(:school_term_type_step) do
      create(:school_term_type_step, school_term_type: school_term_type, step_number: 1)
    end
    before do
      4.times do |n|
        school_calendar.steps.create!(
          step_number: n + 1,
          start_at: Date.new(2026, 2, 1) + (n * 2).months,
          end_at: Date.new(2026, 2, 1) + ((n + 1) * 2).months - 1.day,
          start_date_for_posting: Date.new(2026, 2, 1) + (n * 2).months,
          end_date_for_posting: Date.new(2026, 2, 1) + ((n + 1) * 2).months - 1.day
        )
      end
    end

    it 'ignora a checagem de número da etapa quando o calendário tem quantidade diferente de etapas' do
      date = school_calendar.steps.first.end_at

      expect(school_calendar.school_term_day?(school_term_type_step, date)).to eq(true)
    end

    it 'retorna false quando a data não pertence a nenhuma etapa do calendário' do
      expect(school_calendar.school_term_day?(school_term_type_step, Date.new(2025, 1, 1))).to eq(false)
    end

    it 'prioriza a etapa com o mesmo número do período escolar quando a data coincide com duas etapas' do
      second_step = school_calendar.steps.find_by(step_number: 2)
      third_step = school_calendar.steps.create!(
        step_number: 3,
        start_at: second_step.end_at,
        end_at: second_step.end_at + 2.months,
        start_date_for_posting: second_step.end_at,
        end_date_for_posting: second_step.end_at + 2.months
      )
      school_term_type_step.update!(step_number: 2)
      boundary_date = second_step.end_at.to_date

      expect(school_calendar.school_term_day?(school_term_type_step, boundary_date)).to eq(true)
      expect(third_step.start_at.to_date).to eq(boundary_date)
    end
  end

  describe '#school_day?' do
    before do
      @school_calendar = build(:school_calendar, year: 2020, number_of_classes: 5)
      @school_calendar.steps.build(start_at: '2020-02-15',
                                   end_at: '2020-05-01',
                                   start_date_for_posting: '2020-02-15',
                                   end_date_for_posting: '2020-05-01')
      @school_calendar.save!
      @school_calendar.events.create(start_date: '2020-04-25', end_date: '2020-04-25', description: 'Dia extra letivo', event_type: EventTypes::EXTRA_SCHOOL)
    end

    context 'when the date is school day with a holiday event' do
      it 'returns false' do
        date = '2020-04-21'.to_date
        expect(@school_calendar.school_day?(date)).to eq(false)
      end
    end

    context 'when the date is a weekend day' do
      it 'returns false' do
        date = '2020-05-03'.to_date
        expect(@school_calendar.school_day?(date)).to eq(false)
      end
    end

    context 'when the date is a weekend day with extra school event' do
      it 'returns true' do
        date = '2020-04-25'.to_date
        expect(@school_calendar.school_day?(date)).to eq(true)
      end
    end

    context 'when the date is school day without a holiday event' do
      it 'returns true' do
        date = '2020-04-20'.to_date
        expect(@school_calendar.school_day?(date)).to eq(true)
      end
    end
  end
end
