require 'rails_helper'

RSpec.describe DescriptiveExamSemesterCalendar do
  let(:unity) { create(:unity) }
  let(:year) { 2024 }
  let(:school_calendar) { create(:school_calendar, unity: unity, year: year) }
  let(:classroom) { create(:classroom, unity: unity, year: year) }

  before do
    create(
      :school_calendar_classroom,
      :school_calendar_classroom_with_four_bimester_steps,
      classroom: classroom,
      school_calendar: school_calendar
    )
  end

  describe '.step_select_options' do
    context 'when semester grouping is disabled' do
      before do
        GeneralConfiguration.current.update(descriptive_exams_semester_calendar_steps: false)
      end

      it 'returns one option per calendar step' do
        options = described_class.step_select_options(classroom)
        expect(options.size).to eq(4)
        expect(options.map { |o| o[:id] }).to match_array(classroom.calendar.classroom_steps.pluck(:id))
      end
    end

    context 'when semester grouping is enabled' do
      before do
        GeneralConfiguration.current.update(descriptive_exams_semester_calendar_steps: true)
      end

      after do
        GeneralConfiguration.current.update(descriptive_exams_semester_calendar_steps: false)
      end

      it 'returns two options anchored on the second and fourth bimesters' do
        options = described_class.step_select_options(classroom)
        steps = classroom.calendar.classroom_steps.order(:step_number).to_a

        expect(options.size).to eq(2)
        expect(options.first[:id]).to eq(steps[1].id)
        expect(options.second[:id]).to eq(steps[3].id)
      end
    end
  end

  describe '.semester_pair_containing' do
    before do
      GeneralConfiguration.current.update(descriptive_exams_semester_calendar_steps: true)
    end

    after do
      GeneralConfiguration.current.update(descriptive_exams_semester_calendar_steps: false)
    end

    it 'returns the first pair for step numbers 1 and 2' do
      pair = described_class.semester_pair_containing(classroom, 2)
      expect(pair.map(&:step_number)).to eq([1, 2])
    end

    it 'returns the second pair for step numbers 3 and 4' do
      pair = described_class.semester_pair_containing(classroom, 3)
      expect(pair.map(&:step_number)).to eq([3, 4])
    end
  end

  context 'with a two-step classroom calendar' do
    let(:classroom_two) { create(:classroom, unity: unity, year: year) }

    before do
      create(
        :school_calendar_classroom,
        :school_calendar_classroom_with_semester_steps,
        classroom: classroom_two,
        school_calendar: school_calendar
      )
    end

    describe '.step_select_options' do
      before do
        GeneralConfiguration.current.update(descriptive_exams_semester_calendar_steps: true)
      end

      after do
        GeneralConfiguration.current.update(descriptive_exams_semester_calendar_steps: false)
      end

      it 'returns a single semester option anchored on the second step' do
        options = described_class.step_select_options(classroom_two)
        steps = classroom_two.calendar.classroom_steps.order(:step_number).to_a

        expect(options.size).to eq(1)
        expect(options.first[:id]).to eq(steps.last.id)
      end
    end

    describe '.semester_pair_containing' do
      before do
        GeneralConfiguration.current.update(descriptive_exams_semester_calendar_steps: true)
      end

      after do
        GeneralConfiguration.current.update(descriptive_exams_semester_calendar_steps: false)
      end

      it 'returns both steps for anchor 1 or 2' do
        pair = described_class.semester_pair_containing(classroom_two, 1)
        expect(pair.map(&:step_number)).to eq([1, 2])

        pair2 = described_class.semester_pair_containing(classroom_two, 2)
        expect(pair2.map(&:step_number)).to eq([1, 2])
      end
    end
  end
end
