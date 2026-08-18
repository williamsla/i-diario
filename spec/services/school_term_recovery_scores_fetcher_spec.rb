require 'rails_helper'

RSpec.describe SchoolTermRecoveryScoresFetcher, type: :service do
  describe '.recovery_step_for' do
    let(:step1) { double(to_number: 1, step_number: 1) }
    let(:step2) { double(to_number: 2, step_number: 2) }
    let(:step3) { double(to_number: 3, step_number: 3) }
    let(:step4) { double(to_number: 4, step_number: 4) }

    it 'returns nil when the semester has no steps' do
      classroom = double(first_exam_rule_with_recovery: nil)

      expect(described_class.recovery_step_for(classroom, [])).to be_nil
    end

    it 'returns the last semester step when there is no specific recovery rule' do
      classroom = double(
        first_exam_rule_with_recovery: double(
          recovery_type: RecoveryTypes::PARALLEL,
          recovery_exam_rules: []
        )
      )

      expect(described_class.recovery_step_for(classroom, [step1, step2])).to eq(step2)
    end

    it 'returns the last step of the matching recovery exam rule' do
      classroom = double(
        first_exam_rule_with_recovery: double(
          recovery_type: RecoveryTypes::SPECIFIC,
          recovery_exam_rules: [
            double(steps: [1, 2]),
            double(steps: [3, 4])
          ]
        )
      )

      expect(described_class.recovery_step_for(classroom, [step1, step2])).to eq(step2)
      expect(described_class.recovery_step_for(classroom, [step3, step4])).to eq(step4)
    end

    it 'returns the semester step itself on two-step calendars' do
      classroom = double(
        first_exam_rule_with_recovery: double(
          recovery_type: RecoveryTypes::SPECIFIC,
          recovery_exam_rules: [
            double(steps: [1]),
            double(steps: [2])
          ]
        )
      )

      expect(described_class.recovery_step_for(classroom, [step1])).to eq(step1)
      expect(described_class.recovery_step_for(classroom, [step2])).to eq(step2)
    end

    it 'returns the last matching recovery step when both semester rules apply' do
      classroom = double(
        first_exam_rule_with_recovery: double(
          recovery_type: RecoveryTypes::SPECIFIC,
          recovery_exam_rules: [
            double(steps: [1]),
            double(steps: [2])
          ]
        )
      )

      expect(described_class.recovery_step_for(classroom, [step1, step2])).to eq(step2)
    end
  end

  describe '#score_for' do
    let(:discipline) { create(:discipline) }
    let(:classroom) {
      create(
        :classroom,
        :with_classroom_semester_steps,
        :score_type_numeric_and_concept_create_rule
      )
    }
    let(:student) { create(:student) }
    let(:first_step) { classroom.calendar.classroom_steps.find_by(step_number: 1) }
    let(:second_step) { classroom.calendar.classroom_steps.find_by(step_number: 2) }
    let(:current_user) { create(:user) }

    def create_recovery_for(step, score)
      recovery_diary_record = create(
        :recovery_diary_record,
        :with_teacher_discipline_classroom,
        unity: classroom.unity,
        classroom: classroom,
        discipline: discipline,
        recorded_at: step.start_at + 1.day,
        students: [
          build(
            :recovery_diary_record_student,
            recovery_diary_record: nil,
            student: student,
            score: score
          )
        ]
      )

      current_user.current_classroom_id = classroom.id
      current_user.current_discipline_id = discipline.id
      allow(recovery_diary_record).to receive(:current_user).and_return(current_user)
      recovery_diary_record.current_user = current_user

      create(
        :school_term_recovery_diary_record,
        recovery_diary_record: recovery_diary_record,
        step_id: step.id,
        step_number: step.step_number,
        recorded_at: recovery_diary_record.recorded_at
      )
    end

    it 'keeps first semester recovery even when recorded_at falls in the second semester' do
      recovery = create_recovery_for(first_step, 6.5)
      recovery.update_columns(recorded_at: second_step.start_at + 1.day)
      recovery.recovery_diary_record.update_columns(recorded_at: second_step.start_at + 1.day)

      fetcher = described_class.new(classroom, discipline, [first_step, second_step])

      expect(fetcher.score_for(student.id, first_step).to_f).to eq(6.5)
      expect(fetcher.score_for(student.id, second_step)).to be_nil
    end
  end
end
