require 'rails_helper'

RSpec.describe ObservationDiaryRecord do
  let(:current_user) { create(:user) }
  let(:classroom) {
    create(
      :classroom,
      :with_classroom_semester_steps,
      :by_discipline
    )
  }

  subject {
    create(
      :observation_diary_record,
      :with_teacher_discipline_classroom,
      :with_notes,
      classroom: classroom
    )
  }

  before do
    current_user.current_classroom_id = subject.classroom_id
    current_user.current_discipline_id = subject.discipline_id
    allow(subject).to receive(:current_user).and_return(current_user)
  end

  describe 'associations' do
    it { expect(subject).to belong_to(:school_calendar) }
    it { expect(subject).to belong_to(:teacher) }
    it { expect(subject).to belong_to(:classroom) }
    it { expect(subject).to belong_to(:discipline) }
    it { expect(subject).to have_many(:notes).dependent(:destroy) }
  end

  describe 'validations' do
    it { expect(subject).to validate_presence_of(:school_calendar) }
    it { expect(subject).to validate_presence_of(:classroom) }
    it { expect(subject).to validate_presence_of(:date) }
    it { expect(subject).to validate_not_in_future_of(:date) }
    it { expect(subject).to validate_school_calendar_day_of(:date) }
    it { expect(subject).to validate_presence_of(:notes) }
    it {
      new_record = build(
        :observation_diary_record,
        :with_teacher_discipline_classroom,
        :with_notes,
        classroom: classroom,
        requires_discipline: true
      )
      expect(new_record).to validate_presence_of(:discipline)
    }

    it 'allows creating without discipline when requires_discipline is false' do
      observation_diary_record = build(
        :observation_diary_record,
        :with_notes,
        classroom: classroom,
        teacher: subject.teacher,
        discipline: nil,
        requires_discipline: false
      )

      expect(observation_diary_record).to be_valid
    end

    it 'allows multiple records on the same date for the same classroom and discipline' do
      observation_diary_record = build(
        :observation_diary_record,
        :with_notes,
        classroom: classroom,
        teacher: subject.teacher,
        discipline: subject.discipline,
        date: subject.date,
        school_calendar: subject.school_calendar
      )

      expect(observation_diary_record).to be_valid
    end
  end
end
