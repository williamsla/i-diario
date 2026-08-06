# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchoolSaturdaysMapping do
  let(:unity) { create(:unity) }
  let(:school_calendar) { create(:school_calendar, :with_one_step, unity: unity, year: 2025) }
  let(:saturday) { Date.parse('2025-01-11') }

  describe '#weekday_name_for' do
    it 'retorna o dia equivalente cadastrado no evento do calendário' do
      create(
        :school_calendar_event,
        school_calendar: school_calendar,
        coverage: EventCoverageType::BY_UNITY,
        start_date: saturday,
        end_date: saturday,
        event_type: EventTypes::EXTRA_SCHOOL,
        equivalent_weekday: Workdays::MONDAY,
        periods: Periods.list
      )

      mapping = described_class.new(school_calendar: school_calendar)

      expect(mapping.weekday_name_for(saturday)).to eq('monday')
    end

    it 'retorna o próprio dia da semana quando não é sábado letivo mapeado' do
      monday = Date.parse('2025-01-13')
      mapping = described_class.new(school_calendar: school_calendar)

      expect(mapping.weekday_name_for(monday)).to eq('monday')
    end
  end

  describe '#saturday_school_day_without_equivalent_weekday?' do
    let(:classroom) { create(:classroom, unity: unity, school_calendar: school_calendar) }
    let(:saturday) { Date.parse('2025-06-14') }

    before do
      create(:classrooms_grade, classroom: classroom, grade: create(:grade))
    end

    it 'retorna true para sábado letivo sem dia equivalente' do
      create(
        :school_calendar_event,
        school_calendar: school_calendar,
        coverage: EventCoverageType::BY_UNITY,
        start_date: saturday,
        end_date: saturday,
        event_type: EventTypes::EXTRA_SCHOOL,
        equivalent_weekday: nil,
        periods: Periods.list
      )

      mapping = described_class.new(school_calendar: school_calendar)

      expect(mapping.saturday_school_day_without_equivalent_weekday?(saturday, classroom: classroom)).to eq(true)
    end

    it 'retorna false quando o sábado letivo possui dia equivalente' do
      create(
        :school_calendar_event,
        school_calendar: school_calendar,
        coverage: EventCoverageType::BY_UNITY,
        start_date: saturday,
        end_date: saturday,
        event_type: EventTypes::EXTRA_SCHOOL,
        equivalent_weekday: Workdays::MONDAY,
        periods: Periods.list
      )

      mapping = described_class.new(school_calendar: school_calendar)

      expect(mapping.saturday_school_day_without_equivalent_weekday?(saturday, classroom: classroom)).to eq(false)
    end
  end
end
