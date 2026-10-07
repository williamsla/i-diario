require 'rails_helper'

RSpec.describe MonthlyAbsenceByStudentFetcher do
  describe '.call' do
    let(:unity) { create(:unity, api_code: '12345') }
    let(:grade) { create(:grade) }
    let(:classroom) { create(:classroom, unity: unity, year: 2026) }
    let(:other_classroom) { create(:classroom, unity: unity, year: 2026) }
    let(:student) { create(:student, name: 'Ana Silva') }
    let(:other_student) { create(:student, name: 'Bruno Costa') }
    let(:school_calendar) { create(:school_calendar, unity: unity, year: 2026) }
    let(:frequency_date) { Date.new(2026, 2, 10) }

    before do
      create(:classrooms_grade, classroom: classroom, grade: grade)
      create(:classrooms_grade, classroom: other_classroom, grade: grade)

      [classroom, other_classroom].each do |target_classroom|
        daily_frequency = create(
          :daily_frequency,
          unity: unity,
          classroom: target_classroom,
          school_calendar: school_calendar,
          frequency_date: frequency_date
        )

        target_student = target_classroom == classroom ? student : other_student

        create(
          :daily_frequency_student,
          daily_frequency: daily_frequency,
          student: target_student,
          present: false,
          active: true
        )
      end
    end

    it 'returns absence count grouped by student and month' do
      rows = described_class.call(unity_api_code: unity.api_code, year: 2026, months: [2])

      expect(rows.size).to eq(2)
      expect(rows.first.student_name).to eq(student.name)
      expect(rows.first.absences_by_month[2]).to eq(1)
      expect(rows.first.frequencies_by_month[2]).to eq(1)
    end

    it 'counts presence days in the frequency total of each month' do
      create(
        :daily_frequency,
        unity: unity,
        classroom: classroom,
        school_calendar: school_calendar,
        frequency_date: Date.new(2026, 2, 11)
      ).tap do |daily_frequency|
        create(
          :daily_frequency_student,
          daily_frequency: daily_frequency,
          student: student,
          present: true,
          active: true
        )
      end

      create(
        :daily_frequency,
        unity: unity,
        classroom: classroom,
        school_calendar: school_calendar,
        frequency_date: Date.new(2026, 3, 4)
      ).tap do |daily_frequency|
        create(
          :daily_frequency_student,
          daily_frequency: daily_frequency,
          student: student,
          present: true,
          active: true
        )
      end

      rows = described_class.call(unity_api_code: unity.api_code, year: 2026, months: [2, 3], classroom_id: classroom.id)
      row = rows.first

      expect(row.absences_by_month[2]).to eq(1)
      expect(row.frequencies_by_month[2]).to eq(2)
      expect(row.absences_by_month[3]).to be_nil
      expect(row.frequencies_by_month[3]).to eq(1)
      expect(described_class.presence_percentage(1, 2)).to eq(50.0)
      expect(described_class.presence_percentage(0, 1)).to eq(100.0)
      expect(described_class.presence_percentage(0, 0)).to be_nil
    end

    it 'includes students who have frequency and no absences' do
      present_student = create(:student, name: 'Carla Dias')
      daily_frequency = create(
        :daily_frequency,
        unity: unity,
        classroom: classroom,
        school_calendar: school_calendar,
        frequency_date: Date.new(2026, 2, 12)
      )

      create(
        :daily_frequency_student,
        daily_frequency: daily_frequency,
        student: present_student,
        present: true,
        active: true
      )

      rows = described_class.call(
        unity_api_code: unity.api_code,
        year: 2026,
        months: [2],
        classroom_id: classroom.id
      )
      present_row = rows.find { |row| row.student_name == present_student.name }

      expect(present_row).to be_present
      expect(present_row.absences_by_month[2]).to be_nil
      expect(present_row.frequencies_by_month[2]).to eq(1)
    end

    it 'filters by classroom' do
      rows = described_class.call(
        unity_api_code: unity.api_code,
        year: 2026,
        months: [2],
        classroom_id: classroom.id
      )

      expect(rows.size).to eq(1)
      expect(rows.first.student_name).to eq(student.name)
    end

    it 'filters by grade' do
      rows = described_class.call(
        unity_api_code: unity.api_code,
        year: 2026,
        months: [2],
        grade_id: grade.id
      )

      expect(rows.size).to eq(2)
    end

    it 'sorts by absences count descending' do
      extra_date = Date.new(2026, 2, 11)
      daily_frequency = create(
        :daily_frequency,
        unity: unity,
        classroom: other_classroom,
        school_calendar: school_calendar,
        frequency_date: extra_date
      )

      create(
        :daily_frequency_student,
        daily_frequency: daily_frequency,
        student: other_student,
        present: false,
        active: true
      )

      rows = described_class.call(
        unity_api_code: unity.api_code,
        year: 2026,
        months: [2],
        sort_by: MonthlyAbsenceReportSortOrders::ABSENCES_COUNT
      )

      expect(rows.first.student_name).to eq(other_student.name)
      expect(rows.last.student_name).to eq(student.name)
    end

    it 'returns empty array when months is empty' do
      rows = described_class.call(unity_api_code: unity.api_code, year: 2026, months: [])

      expect(rows).to eq([])
    end
  end
end
