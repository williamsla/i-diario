require 'rails_helper'

RSpec.describe PendingRecordsFinalRecoverySummary, type: :service do
  let(:exam_rule) { create(:exam_rule, score_type: ScoreTypes::NUMERIC, final_recovery_maximum_score: 10) }
  let(:classroom) { create(:classroom, :score_type_numeric, :with_classroom_semester_steps, exam_rule: exam_rule) }
  let(:school_calendar) { SchoolCalendar.find_by!(unity_id: classroom.unity_id, year: classroom.year) }
  let(:discipline) { create(:discipline) }
  let(:students) { create_list(:student, 3) }
  let(:fetcher) { instance_double(StudentsInFinalRecoveryFetcher) }

  around do |example|
    memory_store = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(memory_store)
    example.run
  end

  before do
    allow(StudentsInFinalRecoveryFetcher).to receive(:new).and_return(fetcher)
    allow(fetcher).to receive(:fetch).with(classroom.id, discipline.id).and_return(students)
    allow(Honeybadger).to receive(:notify)
  end

  describe '.available_for?' do
    it 'returns true for numeric classroom with final recovery maximum score' do
      expect(described_class.available_for?(classroom)).to eq(true)
    end

    it 'returns false when final recovery maximum score is zero' do
      exam_rule.update!(final_recovery_maximum_score: 0)

      expect(described_class.available_for?(classroom)).to eq(false)
    end

    it 'returns false for conceptual classroom' do
      conceptual_exam_rule = create(:exam_rule, :score_type_concept, final_recovery_maximum_score: 10)
      conceptual_classroom = create(:classroom, :score_type_concept, exam_rule: conceptual_exam_rule)

      expect(described_class.available_for?(conceptual_classroom)).to eq(false)
    end
  end

  describe '#counts' do
    subject do
      described_class.new(
        classroom: classroom,
        school_calendar: school_calendar,
        discipline_ids: [discipline.id]
      )
    end

    it 'counts eligible students without a launched final recovery score' do
      expect(subject.counts[discipline.id]).to eq(3)
    end

    it 'does not count students who already have a final recovery score' do
      create_final_recovery_diary(
        scored_students: [students.first, students.second],
        students_without_score: [students.third]
      )

      expect(subject.counts[discipline.id]).to eq(1)
    end

    it 'keeps the student without score pending after the diary is saved' do
      create_final_recovery_diary(
        scored_students: [students.first, students.second],
        students_without_score: [students.third]
      )

      expect(subject.counts[discipline.id]).to eq(1)

      recovery_student = RecoveryDiaryRecordStudent.find_by!(student: students.third)
      recovery_student.update!(score: 7)

      expect(
        described_class.new(
          classroom: classroom,
          school_calendar: school_calendar,
          discipline_ids: [discipline.id]
        ).counts[discipline.id]
      ).to eq(0)
    end

    it 'does not recache pending scores: a later local save is visible immediately' do
      expect(subject.counts[discipline.id]).to eq(3)

      create_final_recovery_diary(
        scored_students: students,
        students_without_score: []
      )

      expect(
        described_class.new(
          classroom: classroom,
          school_calendar: school_calendar,
          discipline_ids: [discipline.id]
        ).counts[discipline.id]
      ).to eq(0)
    end

    it 'marks the discipline as error when iEducar fetch fails' do
      allow(fetcher).to receive(:fetch).and_raise(StandardError, 'api down')

      expect(subject.counts).to eq({})
      expect(subject.errors[discipline.id]).to eq(true)
      expect(Honeybadger).to have_received(:notify)
    end
  end

  def create_final_recovery_diary(scored_students:, students_without_score:)
    recovery_diary_record = build(
      :recovery_diary_record,
      :with_teacher_discipline_classroom,
      classroom: classroom,
      discipline: discipline
    )

    scored_students.each do |student|
      recovery_diary_record.students.build(student: student, score: 6)
    end

    students_without_score.each do |student|
      recovery_diary_record.students.build(student: student, score: nil)
    end

    recovery_diary_record.save!

    create(
      :final_recovery_diary_record,
      recovery_diary_record: recovery_diary_record,
      school_calendar: school_calendar
    )
  end
end
