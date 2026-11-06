require 'rails_helper'

RSpec.describe LessonsBoard, type: :model do
  subject {
    build(
      :lessons_board
    )
  }

  describe 'associations' do
    it { expect(subject).to belong_to(:classrooms_grade) }
  end

  describe 'validations' do
    it { expect(subject).to validate_presence_of(:period) }
    it { expect(subject).to validate_presence_of(:classrooms_grade_id) }
  end

  describe '.ids_covering_date' do
    let(:classroom) { create(:classroom, year: 2026) }
    let(:classrooms_grade) { create(:classrooms_grade, classroom: classroom) }
    let(:teacher_discipline_classroom) { create(:teacher_discipline_classroom, classroom: classroom, year: 2026) }
    let(:archive_date) { Date.new(2026, 7, 27) }
    let(:calendar) { instance_double(SchoolCalendar, first_day: Date.new(2026, 1, 1)) }

    before do
      allow_any_instance_of(CurrentSchoolCalendarFetcher).to receive(:fetch).and_return(calendar)
    end

    it 'usa o quadro arquivado até a data de arquivamento e o ativo depois dela' do
      archived = create(:lessons_board, classrooms_grade: classrooms_grade)
      archived_lesson = create(:lessons_board_lesson, lessons_board: archived, lesson_number: 1)
      create(
        :lessons_board_lesson_weekday,
        lessons_board_lesson: archived_lesson,
        teacher_discipline_classroom: teacher_discipline_classroom,
        weekday: 'monday'
      )
      archived.discard
      archived.update_column(:discarded_at, archive_date.end_of_day)

      active = create(:lessons_board, classrooms_grade: classrooms_grade)
      active_lesson = create(:lessons_board_lesson, lessons_board: active, lesson_number: 2)
      create(
        :lessons_board_lesson_weekday,
        lessons_board_lesson: active_lesson,
        teacher_discipline_classroom: teacher_discipline_classroom,
        weekday: 'wednesday'
      )

      expect(described_class.discarded_at_as_local_date(archived.reload.discarded_at)).to eq(archive_date)
      expect(described_class.ids_covering_date(classroom.id, archive_date)).to eq([archived.id])
      expect(described_class.ids_covering_date(classroom.id, archive_date + 1.day)).to eq([active.id])

      monday_allocations = described_class.allocations_on_date(
        classroom_id: classroom.id,
        date: archive_date,
        weekday: 'monday',
        discipline_id: teacher_discipline_classroom.discipline_id
      )
      expect(monday_allocations.map { |allocation| allocation.lessons_board_lesson.lesson_number }).to eq([1])

      later_monday = described_class.allocations_on_date(
        classroom_id: classroom.id,
        date: Date.new(2026, 8, 3),
        weekday: 'monday',
        discipline_id: teacher_discipline_classroom.discipline_id
      )
      expect(later_monday).to eq([])
    end
  end
end
