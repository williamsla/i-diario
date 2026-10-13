# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchoolDayChecker do
  let(:unity) { create(:unity) }
  let(:school_calendar) { create(:school_calendar, :with_one_step, unity: unity) }
  let(:grade) { create(:grade) }
  let(:classroom) do
    create(
      :classroom,
      unity: unity,
      year: school_calendar.year,
      period: Periods::FULL
    )
  end

  before do
    create(
      :classrooms_grade,
      classroom: classroom,
      grade: grade
    )
    create(
      :school_calendar_event,
      school_calendar: school_calendar,
      coverage: EventCoverageType::BY_UNITY,
      event_type: EventTypes::NO_SCHOOL,
      start_date: Date.new(school_calendar.year, 4, 15),
      end_date: Date.new(school_calendar.year, 4, 15),
      periods: %w[2],
      legend: 'P',
      description: 'Ponto facultativo vespertino'
    )
  end

  it 'blocks entry for the vespertine period' do
    checker = described_class.new(
      school_calendar,
      Date.new(school_calendar.year, 4, 15),
      grade.id,
      classroom.id,
      nil,
      Periods::VESPERTINE
    )

    expect(checker.day_allows_entry?).to eq(false)
  end

  it 'allows entry for the matutinal period of an integral classroom' do
    checker = described_class.new(
      school_calendar,
      Date.new(school_calendar.year, 4, 15),
      grade.id,
      classroom.id,
      nil,
      Periods::MATUTINAL
    )

    expect(checker.day_allows_entry?).to eq(true)
  end
end
