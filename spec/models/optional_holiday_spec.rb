# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionalHoliday, type: :model do
  subject { build(:optional_holiday) }

  describe 'validations' do
    it { expect(subject).to validate_presence_of(:year) }
    it { expect(subject).to validate_presence_of(:holiday_date) }
    it { expect(subject).to validate_presence_of(:description) }
    it { expect(subject).to validate_presence_of(:makeup_scope) }
    it { expect(subject).to validate_presence_of(:user) }
    it { expect(subject).to validate_presence_of(:periods) }

    it 'does not allow two holidays on the same date in the same year' do
      existing = create(:optional_holiday)
      duplicate = build(
        :optional_holiday,
        year: existing.year,
        holiday_date: existing.holiday_date,
        user: existing.user
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:holiday_date]).to be_present
    end

    it 'rejects a make up date before the holiday' do
      holiday = build(
        :optional_holiday,
        holiday_date: Date.current,
        make_up_date: Date.current - 1.day
      )

      expect(holiday).not_to be_valid
      expect(holiday.errors[:make_up_date]).to be_present
    end

    it 'assigns the holiday weekday when the make up date is Saturday' do
      holiday = build(
        :optional_holiday,
        holiday_date: Date.new(2026, 8, 28),
        make_up_date: Date.new(2026, 8, 29)
      )

      expect(holiday).to be_valid
      expect(holiday.equivalent_weekday).to eq(Workdays::FRIDAY)
    end

    it 'does not assign an equivalent weekday when the make up date is not Saturday' do
      holiday = build(
        :optional_holiday,
        holiday_date: Date.new(2026, 8, 28),
        make_up_date: Date.new(2026, 8, 31)
      )

      expect(holiday).to be_valid
      expect(holiday.equivalent_weekday).to be_nil
    end
  end

  describe '.equivalent_weekday_for_make_up' do
    it 'maps Saturday make up to the weekday of the holiday' do
      expect(
        described_class.equivalent_weekday_for_make_up(
          Date.new(2026, 8, 25),
          Date.new(2026, 8, 29)
        )
      ).to eq(Workdays::TUESDAY)
    end

    it 'returns nil when the make up date is not Saturday' do
      expect(
        described_class.equivalent_weekday_for_make_up(
          Date.new(2026, 8, 28),
          Date.new(2026, 8, 31)
        )
      ).to be_nil
    end
  end

  describe '.format_pending_date' do
    it 'appends the makeup label when the date is a make up date' do
      expect(
        described_class.format_pending_date(
          Date.new(2026, 8, 29),
          [Date.new(2026, 8, 29)]
        )
      ).to eq('29/08/2026 (reposição)')
    end

    it 'keeps a regular school date without the makeup label' do
      expect(
        described_class.format_pending_date(
          Date.new(2026, 8, 28),
          [Date.new(2026, 8, 29)]
        )
      ).to eq('28/08/2026')
    end
  end

  describe '#applies_to_period?' do
    let(:holiday) { build(:optional_holiday, periods: %w[2]) }

    it 'matches the informed period' do
      expect(holiday.applies_to_period?(Periods::VESPERTINE)).to eq(true)
    end

    it 'does not match another period' do
      expect(holiday.applies_to_period?(Periods::MATUTINAL)).to eq(false)
    end
  end

  describe '.blocks_frequency?' do
    let(:unity) { create(:unity) }
    let(:classroom) { create(:classroom, unity: unity, period: Periods::VESPERTINE, year: Date.current.year) }

    before do
      create(
        :optional_holiday,
        year: classroom.year,
        holiday_date: Date.current,
        periods: %w[2]
      )
    end

    it 'blocks the vespertine classroom on the holiday date' do
      expect(
        described_class.blocks_frequency?(
          classroom: classroom,
          date: Date.current,
          period: Periods::VESPERTINE
        )
      ).to eq(true)
    end

    it 'does not block the matutinal period' do
      expect(
        described_class.blocks_frequency?(
          classroom: classroom,
          date: Date.current,
          period: Periods::MATUTINAL
        )
      ).to eq(false)
    end
  end

  describe '.make_up_dates_for' do
    let(:unity) { create(:unity) }
    let(:classroom) { create(:classroom, unity: unity, period: Periods::VESPERTINE, year: Date.current.year) }
    let(:holiday_date) { Date.current }
    let(:make_up_date) { Date.current + 2.days }

    it 'returns the municipal make up date' do
      create(
        :optional_holiday,
        year: classroom.year,
        holiday_date: holiday_date,
        make_up_date: make_up_date,
        periods: %w[2],
        makeup_scope: OptionalHolidayMakeupScope::MUNICIPAL
      )

      dates = described_class.make_up_dates_for(
        classroom: classroom,
        start_date: holiday_date,
        end_date: make_up_date,
        period: Periods::VESPERTINE
      )

      expect(dates).to include(make_up_date)
    end

    it 'returns the school make up date when the scope is by school' do
      holiday = create(
        :optional_holiday,
        year: classroom.year,
        holiday_date: holiday_date,
        periods: %w[2],
        makeup_scope: OptionalHolidayMakeupScope::BY_SCHOOL
      )
      create(
        :optional_holiday_unity_makeup,
        optional_holiday: holiday,
        unity: unity,
        make_up_date: make_up_date
      )

      dates = described_class.make_up_dates_for(
        classroom: classroom,
        start_date: holiday_date,
        end_date: make_up_date,
        period: Periods::VESPERTINE
      )

      expect(dates).to include(make_up_date)
    end
  end
end

RSpec.describe OptionalHolidayUnityMakeup, type: :model do
  it 'assigns the holiday weekday when the make up date is Saturday' do
    holiday = create(
      :optional_holiday,
      holiday_date: Date.new(2026, 8, 28),
      makeup_scope: OptionalHolidayMakeupScope::BY_SCHOOL
    )
    makeup = build(
      :optional_holiday_unity_makeup,
      optional_holiday: holiday,
      make_up_date: Date.new(2026, 8, 29)
    )

    expect(makeup).to be_valid
    expect(makeup.equivalent_weekday).to eq(Workdays::FRIDAY)
  end
end
