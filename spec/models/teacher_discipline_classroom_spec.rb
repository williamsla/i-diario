require 'rails_helper'

RSpec.describe TeacherDisciplineClassroom, type: :model do
  let(:teacher) { create(:teacher) }
  let(:classroom) { create(:classroom) }
  let(:discipline) { create(:discipline) }

  def create_link(attributes = {})
    create(
      :teacher_discipline_classroom,
      {
        teacher: teacher,
        classroom: classroom,
        discipline: discipline,
        year: classroom.year
      }.merge(attributes)
    )
  end

  describe '.left_at_for' do
    it 'não marca saída quando a professora retornou e o vínculo atual está vigente' do
      travel_to Date.new(2026, 11, 19) do
        create_link(
          start_at: Date.new(2026, 2, 2),
          end_at: Date.new(2026, 3, 31),
          allocation_left_at: Date.new(2026, 3, 31)
        )
        create_link(
          start_at: Date.new(2026, 5, 18),
          end_at: nil,
          allocation_left_at: Date.new(2026, 3, 31)
        )

        expect(
          described_class.left_at_for(teacher_id: teacher.id, classroom_id: classroom.id)
        ).to be_nil
      end
    end

    it 'marca a saída quando não há vínculo vigente' do
      travel_to Date.new(2026, 11, 19) do
        create_link(
          start_at: Date.new(2026, 2, 2),
          end_at: Date.new(2026, 3, 31),
          allocation_left_at: Date.new(2026, 3, 31)
        )

        expect(
          described_class.left_at_for(teacher_id: teacher.id, classroom_id: classroom.id)
        ).to eq(Date.new(2026, 3, 31))
      end
    end
  end
end
