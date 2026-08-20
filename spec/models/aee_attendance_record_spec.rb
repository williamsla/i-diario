require 'rails_helper'

RSpec.describe AeeAttendanceRecord do
  subject { build(:aee_attendance_record) }

  describe 'associations' do
    it { expect(subject).to belong_to(:unity) }
    it { expect(subject).to belong_to(:classroom) }
    it { expect(subject).to belong_to(:student) }
    it { expect(subject).to belong_to(:teacher) }
    it { expect(subject).to belong_to(:user) }
    it { expect(subject).to belong_to(:school_calendar) }
  end

  describe 'validations' do
    it { expect(subject).to validate_presence_of(:unity) }
    it { expect(subject).to validate_presence_of(:classroom) }
    it { expect(subject).to validate_presence_of(:student) }
    it { expect(subject).to validate_presence_of(:teacher) }
    it { expect(subject).to validate_presence_of(:year) }
    it { expect(subject).to validate_presence_of(:record_date) }
    it { expect(subject).to validate_presence_of(:activities_developed) }

    it 'does not allow a second record for the same student, classroom and date' do
      existing = create(:aee_attendance_record)
      duplicate = build(
        :aee_attendance_record,
        classroom: existing.classroom,
        student: existing.student,
        record_date: existing.record_date,
        unity: existing.unity,
        school_calendar: existing.school_calendar
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:student_id]).to be_present
    end
  end

  describe '#apply_defaults!' do
    it 'copies goals and duration from the PEI and PAEE' do
      record = build(:aee_attendance_record, session_objectives: nil, duration: nil)
      pei = create(
        :aee_individual_plan,
        student: record.student,
        classroom: record.classroom,
        unity: record.unity,
        year: record.year,
        school_calendar: record.school_calendar,
        goals: 'Metas do PEI'
      )
      teaching_plan = create(
        :teaching_plan,
        student: record.student,
        year: record.year
      )
      teaching_plan.create_aee_teaching_plan_detail!(
        attendance_duration: '50 minutos'
      )

      record.apply_defaults!

      expect(record.aee_individual_plan).to eq(pei)
      expect(record.session_objectives).to eq('Metas do PEI')
      expect(record.duration).to eq('50 minutos')
    end
  end
end
