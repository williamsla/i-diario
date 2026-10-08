require 'rails_helper'

RSpec.describe StudentEnrollmentDateRanges, type: :service do
  let(:classroom) { create(:classroom, year: 2026, period: Periods::VESPERTINE) }
  let(:classrooms_grade) { create(:classrooms_grade, classroom: classroom) }
  let(:student_enrollment) { create(:student_enrollment) }
  let(:student_id) { student_enrollment.student_id }

  let!(:enrollment_before_transfer) do
    create(
      :student_enrollment_classroom,
      student_enrollment: student_enrollment,
      classrooms_grade: classrooms_grade,
      joined_at: '2026-02-02',
      left_at: '2026-05-08'
    )
  end

  let!(:enrollment_after_return) do
    create(
      :student_enrollment_classroom,
      student_enrollment: student_enrollment,
      classrooms_grade: classrooms_grade,
      joined_at: '2026-05-13',
      left_at: ''
    )
  end

  subject(:ranges) do
    described_class.for(classroom_id: classroom.id, student_ids: [student_id])
  end

  it 'considera enturmado o período anterior à transferência' do
    expect(ranges.cover?(student_id, Date.new(2026, 5, 7))).to eq(true)
  end

  it 'considera não enturmado o intervalo entre a transferência e o retorno' do
    expect(ranges.cover?(student_id, Date.new(2026, 5, 8))).to eq(false)
    expect(ranges.cover?(student_id, Date.new(2026, 5, 12))).to eq(false)
  end

  it 'considera enturmado a partir da data de retorno' do
    expect(ranges.cover?(student_id, Date.new(2026, 5, 13))).to eq(true)
    expect(ranges.cover?(student_id, Date.new(2026, 6, 1))).to eq(true)
  end
end
