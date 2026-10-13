require 'rails_helper'

RSpec.describe ConceptualExam, type: :model do
  let(:current_user) { create(:user) }

  subject do
    create(
      :conceptual_exam,
      :with_teacher_discipline_classroom,
      :with_student_enrollment_classroom,
      :with_one_value
    )
  end

  before do
    current_user.current_classroom_id = subject.classroom_id
    allow(subject).to receive(:current_user).and_return(current_user)
  end

  describe 'associations' do
    it { expect(subject).to belong_to(:classroom) }
    it { expect(subject).to belong_to(:student) }
    it { expect(subject).to have_many(:conceptual_exam_values) }
  end

  describe 'validations' do
    it { expect(subject).to validate_presence_of(:student) }
    it { expect(subject).to validate_presence_of(:recorded_at) }
    it { expect(subject).to validate_not_in_future_of(:recorded_at) }
    it { expect(subject).to validate_school_term_day_of(:recorded_at) }

    it 'should require student to have conceptual exam score type' do
      invalid_score_types = [ScoreTypes::DONT_USE, ScoreTypes::NUMERIC]
      expected_message = I18n.t(
        '.activerecord.errors.models.conceptual_exam.attributes.student' \
        '.classroom_must_have_conceptual_exam_score_type'
      )

      student = create(:student)
      student_enrollment = create(:student_enrollment, student: student)
      classrooms_grade = create(:classrooms_grade, :score_type_numeric)
      create(
        :student_enrollment_classroom,
        classrooms_grade: classrooms_grade,
        student_enrollment: student_enrollment
      )
      conceptual_exam = build(
        :conceptual_exam,
        :with_teacher_discipline_classroom,
        classroom: classrooms_grade.classroom,
        student: student
      )

      conceptual_exam.student.uses_differentiated_exam_rule = false

      conceptual_exam.valid?

      expect(conceptual_exam.errors[:student]).to include(expected_message)
    end

    context 'enturmação na etapa' do
      let(:expected_message) do
        I18n.t(
          'activerecord.errors.models.conceptual_exam.attributes.base.student_is_not_in_classroom'
        )
      end

      subject do
        build(
          :conceptual_exam,
          :with_teacher_discipline_classroom,
          :with_student_enrollment_classroom,
          :with_one_value
        )
      end

      def enrollment_classroom
        StudentEnrollmentClassroom.by_classroom(subject.classroom_id).by_student(subject.student_id).first
      end

      it 'permite lançar o conceito se o aluno cursou algum dia da etapa, mesmo fora da data do lançamento' do
        step = subject.step
        enrollment_classroom.update!(left_at: (step.start_at.to_date + 10.days).to_s)
        subject.recorded_at = step.end_at

        subject.valid?

        expect(subject.errors[:base]).not_to include(expected_message)
      end

      it 'bloqueia o lançamento se o aluno não cursou nenhum dia da etapa' do
        step = StepsFetcher.new(subject.classroom).steps.second
        subject.step_id = step.id
        subject.step_number = step.step_number
        subject.recorded_at = step.start_at
        enrollment_classroom.update!(left_at: (step.start_at.to_date - 1.day).to_s)

        subject.valid?

        expect(subject.errors[:base]).to include(expected_message)
      end
    end

    context 'recorded_at validations' do
      context 'creating a new conceptual_exam' do
        subject do
          build(
            :conceptual_exam,
            :with_teacher_discipline_classroom,
            :with_student_enrollment_classroom,
            :with_one_value
          )
        end

        context 'when recorded_at is in step range' do
          it { expect(subject.valid?).to be true }
        end

        context 'when recorded_at is out of step range' do
          before do
            subject.recorded_at = subject.step.end_at + 1.day
          end

          it 'requires conceptual_exam to have a recorded_at in step range' do
            expected_message = I18n.t('errors.messages.not_school_term_day')

            subject.valid?

            expect(subject.errors[:recorded_at]).to include(expected_message)
          end
        end
      end

      context 'updating a existing conceptual_exam' do
        context 'when recorded_at is out of step range' do
          context 'recorded_at has not changed' do
            before do
              subject.recorded_at = subject.step.end_at + 1.day
              subject.save!(validate: false)
            end

            it { expect(subject.valid?).to be true }
          end

          context 'recorded_at has changed' do
            before do
              subject.recorded_at = subject.step.end_at + 1.day
            end

            it 'requires conceptual_exam to have a recorded_at in step range' do
              expected_message = I18n.t('errors.messages.not_school_term_day')

              subject.valid?

              expect(subject.errors[:recorded_at]).to include(expected_message)
            end
          end
        end
      end
    end
  end

  describe '#merge_conceptual_exam_values' do
    it 'overrides the new value over the persisted one' do
      conceptual_exam_value = subject.conceptual_exam_values.first

      attributes = {
        conceptual_exam_values_attributes: {
          '1' => {
            discipline_id: conceptual_exam_value.discipline_id,
            value: 200
          },
          '2' => {
            discipline_id: Discipline.first.id,
            value: 300
          }
        }
      }
      subject.assign_attributes(attributes)

      subject.merge_conceptual_exam_values

      expect(subject.conceptual_exam_values.size).to eq 2
      expect(subject.conceptual_exam_values.first.value).to eq 200
      expect(subject.conceptual_exam_values.last.value).to eq 300
    end

    it 'maintains only the persited if do not have new values' do
      conceptual_exam_value = subject.conceptual_exam_values.first

      subject.merge_conceptual_exam_values

      expect(subject.conceptual_exam_values.size).to eq 1
      expect(subject.conceptual_exam_values.first.value).to eq conceptual_exam_value.value
    end
  end
end
