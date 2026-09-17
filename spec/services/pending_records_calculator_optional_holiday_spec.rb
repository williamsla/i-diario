require 'rails_helper'

RSpec.describe PendingRecordsCalculator, type: :service do
  subject(:calculator) { described_class.new(school_year: Date.current.year) }

  describe '#apply_optional_holidays!' do
    let(:unity) { create(:unity) }
    let(:classroom) { create(:classroom, unity: unity, period: Periods::VESPERTINE, year: Date.current.year) }
    let(:holiday_date) { Date.new(Date.current.year, 8, 24) }
    let(:make_up_date) { Date.new(Date.current.year, 8, 29) }

    before do
      create(
        :optional_holiday,
        year: classroom.year,
        holiday_date: holiday_date,
        make_up_date: make_up_date,
        periods: %w[2],
        makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL
      )
      allow(calculator).to receive(:get_equivalent_weekday_number) { |date| date.wday }
      allow(calculator).to receive(:lessons_board_archive_date).and_return(nil)
    end

    def apply_makeups(weekday_numbers:, frequency_dates_set: [], content_dates_set: [])
      pending_frequency_dates = []
      pending_content_dates = []
      makeup_dates = calculator.send(
        :apply_optional_holidays!,
        pending_frequency_dates,
        pending_content_dates,
        classroom,
        classroom.period,
        holiday_date,
        make_up_date,
        Date.current,
        frequency_dates_set: frequency_dates_set,
        content_dates_set: content_dates_set,
        frequency_weekday_numbers: weekday_numbers,
        content_weekday_numbers: weekday_numbers,
        discarded_weekday_numbers: []
      )

      [pending_frequency_dates, pending_content_dates, makeup_dates]
    end

    it 'includes the makeup date when the discipline had class on the optional holiday' do
      pending_frequency_dates, pending_content_dates, makeup_dates = apply_makeups(
        weekday_numbers: [holiday_date.wday]
      )

      expect(pending_frequency_dates).to include(make_up_date)
      expect(pending_content_dates).to include(make_up_date)
      expect(makeup_dates).to include(make_up_date)
    end

    it 'does not include the makeup date when the discipline had no class on the optional holiday' do
      pending_frequency_dates, pending_content_dates, makeup_dates = apply_makeups(
        weekday_numbers: [holiday_date.wday == 1 ? 2 : 1]
      )

      expect(pending_frequency_dates).not_to include(make_up_date)
      expect(pending_content_dates).not_to include(make_up_date)
      expect(makeup_dates).not_to include(make_up_date)
    end

    it 'does not mark the makeup date as pending when frequency and content are already recorded' do
      pending_frequency_dates, pending_content_dates, _makeup_dates = apply_makeups(
        weekday_numbers: [holiday_date.wday],
        frequency_dates_set: [make_up_date],
        content_dates_set: [make_up_date]
      )

      expect(pending_frequency_dates).not_to include(make_up_date)
      expect(pending_content_dates).not_to include(make_up_date)
    end
  end
end
