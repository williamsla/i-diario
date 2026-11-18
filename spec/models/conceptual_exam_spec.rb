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

  describe 'status do professor que está lançando' do
    let(:year) { Date.current.year }
    let(:unity) { create(:unity) }
    let(:school_calendar) { create(:school_calendar, unity: unity, year: year) }
    let(:classroom) do
      create(
        :classroom,
        :with_classroom_semester_steps,
        unity: unity,
        year: year,
        school_calendar: school_calendar
      )
    end
    let(:grade) { create(:grade) }
    let(:other_grade) { create(:grade) }
    let(:exam_rule) { create(:exam_rule, :score_type_concept) }
    let(:classrooms_grade) do
      create(:classrooms_grade, classroom: classroom, grade: grade, exam_rule: exam_rule)
    end
    let(:teacher) { create(:teacher) }
    let(:physical_education_teacher) { create(:teacher) }
    let(:discipline) { create(:discipline, descriptor: true, grouper: false) }
    let(:physical_education) { create(:discipline, descriptor: true, grouper: false) }
    let(:other_grade_discipline) { create(:discipline, descriptor: true, grouper: false) }
    let(:student) { create(:student) }
    let(:student_enrollment) { create(:student_enrollment, student: student) }
    let!(:enrollment_classroom) do
      create(
        :student_enrollment_classroom,
        classrooms_grade: classrooms_grade,
        student_enrollment: student_enrollment,
        joined_at: Date.new(year, 1, 1)
      )
    end

    before do
      create(
        :teacher_discipline_classroom,
        classroom: classroom,
        teacher: teacher,
        discipline: discipline,
        grade: grade,
        year: year,
        score_type: ScoreTypes::CONCEPT
      )
      create(
        :teacher_discipline_classroom,
        classroom: classroom,
        teacher: physical_education_teacher,
        discipline: physical_education,
        grade: grade,
        year: year,
        score_type: ScoreTypes::CONCEPT
      )
      create(
        :teacher_discipline_classroom,
        classroom: classroom,
        teacher: teacher,
        discipline: other_grade_discipline,
        grade: other_grade,
        year: year,
        score_type: ScoreTypes::CONCEPT
      )
      create(:school_calendar_discipline_grade, school_calendar: school_calendar, discipline: discipline, grade: grade)
      create(
        :school_calendar_discipline_grade,
        school_calendar: school_calendar,
        discipline: physical_education,
        grade: grade
      )
      create(
        :school_calendar_discipline_grade,
        school_calendar: school_calendar,
        discipline: other_grade_discipline,
        grade: other_grade
      )
    end

    def create_exam(values_by_discipline)
      exam = build(
        :conceptual_exam,
        classroom: classroom,
        student: student,
        teacher_id: teacher.id,
        unity_id: classroom.unity_id
      )

      values_by_discipline.each do |discipline_record, value|
        exam.conceptual_exam_values.build(
          discipline: discipline_record,
          value: value,
          exempted_discipline: false
        )
      end

      exam.save!
      exam
    end

    it 'fica completo quando a parte da professora está lançada e educação física de outro professor está vazia' do
      exam = create_exam(discipline => 1, physical_education => nil, other_grade_discipline => nil)

      expect(exam.status(teacher.id)).to eq(ConceptualExamStatus::COMPLETE)
      expect(
        ConceptualExam.by_status(classroom.id, teacher.id, ConceptualExamStatus::INCOMPLETE)
      ).not_to include(exam)
      expect(exam.status(physical_education_teacher.id)).to eq(ConceptualExamStatus::INCOMPLETE)
    end

    it 'fica incompleto quando falta conceito numa disciplina da professora' do
      exam = create_exam(discipline => nil)

      expect(exam.status(teacher.id)).to eq(ConceptualExamStatus::INCOMPLETE)
      expect(
        ConceptualExam.by_status(classroom.id, teacher.id, ConceptualExamStatus::INCOMPLETE)
      ).to include(exam)
    end

    it 'ignora disciplina dispensada para o aluno' do
      exam = create_exam(discipline => nil)
      create(
        :student_enrollment_exempted_discipline,
        student_enrollment: student_enrollment,
        discipline: discipline,
        steps: exam.step_number.to_s
      )

      expect(exam.status(teacher.id)).to eq(ConceptualExamStatus::COMPLETE)
    end

    it 'ignora valor vazio marcado como dispensado na ficha' do
      exam = create_exam(discipline => nil)
      exam.conceptual_exam_values.first.update_column(:exempted_discipline, true)

      expect(exam.status(teacher.id)).to eq(ConceptualExamStatus::COMPLETE)
    end

    it 'em turma multisseriada só cobra a série da enturmação do aluno' do
      exam = create_exam(discipline => 1, other_grade_discipline => nil)

      expect(exam.status(teacher.id)).to eq(ConceptualExamStatus::COMPLETE)

      other_student = create(:student)
      other_enrollment = create(:student_enrollment, student: other_student)
      other_classrooms_grade = create(
        :classrooms_grade,
        classroom: classroom,
        grade: other_grade,
        exam_rule: exam_rule
      )
      create(
        :student_enrollment_classroom,
        classrooms_grade: other_classrooms_grade,
        student_enrollment: other_enrollment,
        joined_at: Date.new(year, 1, 1)
      )
      other_exam = build(
        :conceptual_exam,
        classroom: classroom,
        student: other_student,
        teacher_id: teacher.id,
        unity_id: classroom.unity_id
      )
      other_exam.conceptual_exam_values.build(
        discipline: other_grade_discipline,
        value: nil,
        exempted_discipline: false
      )
      other_exam.save!

      expect(other_exam.status(teacher.id)).to eq(ConceptualExamStatus::INCOMPLETE)
    end

    it 'ignora disciplina que a ficha não mostra' do
      hidden_discipline = create(:discipline, descriptor: false, grouper: false)
      grouper_discipline = create(:discipline, descriptor: true, grouper: true)
      [hidden_discipline, grouper_discipline].each do |extra_discipline|
        create(
          :teacher_discipline_classroom,
          classroom: classroom,
          teacher: teacher,
          discipline: extra_discipline,
          grade: grade,
          year: year,
          score_type: ScoreTypes::CONCEPT
        )
        create(
          :school_calendar_discipline_grade,
          school_calendar: school_calendar,
          discipline: extra_discipline,
          grade: grade
        )
      end
      exam = create_exam(discipline => 1, hidden_discipline => nil, grouper_discipline => nil)

      expect(exam.status(teacher.id)).to eq(ConceptualExamStatus::COMPLETE)
    end

    it 'ignora conceito vazio de disciplina fora das etapas específicas' do
      exam = create_exam(discipline => nil)
      create(:specific_step, classroom: classroom, discipline: discipline, used_steps: '9')

      expect(exam.status(teacher.id)).to eq(ConceptualExamStatus::COMPLETE)

      SpecificStep.find_by(classroom: classroom, discipline: discipline)
                  .update!(used_steps: exam.step_number.to_s)

      expect(exam.status(teacher.id)).to eq(ConceptualExamStatus::INCOMPLETE)
    end

    it 'ignora lotação de outro ano' do
      TeacherDisciplineClassroom.where(teacher: teacher, discipline: discipline).update_all(year: year - 1)
      exam = create_exam(discipline => nil)

      expect(exam.status(teacher.id)).to eq(ConceptualExamStatus::COMPLETE)
    end

    it 'usa o professor gravado no exame quando a consulta não informa outro' do
      exam = create_exam(discipline => 1, physical_education => nil)

      expect(exam.status).to eq(ConceptualExamStatus::COMPLETE)
      expect(
        ConceptualExam.by_status(classroom.id, teacher.id, ConceptualExamStatus::COMPLETE)
      ).to include(exam)
    end

    it 'separa completos e incompletos na mesma turma' do
      complete_exam = create_exam(discipline => 1, physical_education => nil)
      other_student = create(:student)
      other_enrollment = create(:student_enrollment, student: other_student)
      create(
        :student_enrollment_classroom,
        classrooms_grade: classrooms_grade,
        student_enrollment: other_enrollment,
        joined_at: Date.new(year, 1, 1)
      )
      incomplete_exam = build(
        :conceptual_exam,
        classroom: classroom,
        student: other_student,
        teacher_id: teacher.id,
        unity_id: classroom.unity_id
      )
      incomplete_exam.conceptual_exam_values.build(
        discipline: discipline,
        value: nil,
        exempted_discipline: false
      )
      incomplete_exam.save!

      complete_scope = ConceptualExam.by_status(classroom.id, teacher.id, ConceptualExamStatus::COMPLETE)
      incomplete_scope = ConceptualExam.by_status(classroom.id, teacher.id, ConceptualExamStatus::INCOMPLETE)

      expect(complete_scope).to include(complete_exam)
      expect(complete_scope).not_to include(incomplete_exam)
      expect(incomplete_scope).to include(incomplete_exam)
      expect(incomplete_scope).not_to include(complete_exam)
    end

    it 'cobra conceito quando a regra é numérica e conceitual e a lotação é de conceito' do
      mixed_rule = create(:exam_rule, :score_type_numeric_and_concept)
      mixed_grade = create(:grade)
      mixed_classrooms_grade = create(
        :classrooms_grade,
        classroom: classroom,
        grade: mixed_grade,
        exam_rule: mixed_rule
      )
      mixed_discipline = create(:discipline, descriptor: true, grouper: false)
      allocation = create(
        :teacher_discipline_classroom,
        classroom: classroom,
        teacher: teacher,
        discipline: mixed_discipline,
        grade: mixed_grade,
        year: year,
        score_type: ScoreTypes::NUMERIC
      )
      create(
        :school_calendar_discipline_grade,
        school_calendar: school_calendar,
        discipline: mixed_discipline,
        grade: mixed_grade
      )
      mixed_student = create(:student)
      mixed_enrollment = create(:student_enrollment, student: mixed_student)
      create(
        :student_enrollment_classroom,
        classrooms_grade: mixed_classrooms_grade,
        student_enrollment: mixed_enrollment,
        joined_at: Date.new(year, 1, 1)
      )
      mixed_exam = build(
        :conceptual_exam,
        classroom: classroom,
        student: mixed_student,
        teacher_id: teacher.id,
        unity_id: classroom.unity_id
      )
      mixed_exam.conceptual_exam_values.build(
        discipline: mixed_discipline,
        value: nil,
        exempted_discipline: false
      )
      mixed_exam.save!

      expect(mixed_exam.status(teacher.id)).to eq(ConceptualExamStatus::COMPLETE)

      allocation.update!(score_type: ScoreTypes::CONCEPT)

      expect(mixed_exam.status(teacher.id)).to eq(ConceptualExamStatus::INCOMPLETE)
    end

    it 'cobra conceito pela regra diferenciada do aluno' do
      numeric_rule = create(:exam_rule)
      differentiated_rule = create(:exam_rule, :score_type_concept)
      numeric_rule.update!(differentiated_exam_rule: differentiated_rule)
      differentiated_grade = create(:grade)
      differentiated_classrooms_grade = create(
        :classrooms_grade,
        classroom: classroom,
        grade: differentiated_grade,
        exam_rule: numeric_rule
      )
      differentiated_discipline = create(:discipline, descriptor: true, grouper: false)
      create(
        :teacher_discipline_classroom,
        classroom: classroom,
        teacher: teacher,
        discipline: differentiated_discipline,
        grade: differentiated_grade,
        year: year,
        score_type: ScoreTypes::CONCEPT
      )
      create(
        :school_calendar_discipline_grade,
        school_calendar: school_calendar,
        discipline: differentiated_discipline,
        grade: differentiated_grade
      )
      differentiated_student = create(:student, uses_differentiated_exam_rule: true)
      differentiated_enrollment = create(:student_enrollment, student: differentiated_student)
      create(
        :student_enrollment_classroom,
        classrooms_grade: differentiated_classrooms_grade,
        student_enrollment: differentiated_enrollment,
        joined_at: Date.new(year, 1, 1)
      )
      differentiated_exam = build(
        :conceptual_exam,
        classroom: classroom,
        student: differentiated_student,
        teacher_id: teacher.id,
        unity_id: classroom.unity_id
      )
      differentiated_exam.conceptual_exam_values.build(
        discipline: differentiated_discipline,
        value: nil,
        exempted_discipline: false
      )
      differentiated_exam.save!

      expect(differentiated_exam.status(teacher.id)).to eq(ConceptualExamStatus::INCOMPLETE)

      differentiated_student.update!(uses_differentiated_exam_rule: false)

      expect(differentiated_exam.status(teacher.id)).to eq(ConceptualExamStatus::COMPLETE)
    end

    it 'não marca pendência sem professor, turma, calendário ou status conhecido' do
      expect(ConceptualExam.by_status(nil, teacher.id, ConceptualExamStatus::INCOMPLETE)).to be_empty
      expect(ConceptualExam.by_status(classroom.id, nil, ConceptualExamStatus::INCOMPLETE)).to be_empty
      expect(ConceptualExam.by_status(classroom.id, teacher.id, 'outro')).to be_empty

      classroom_without_calendar = create(:classroom, unity: unity, year: year + 1)
      expect(
        ConceptualExam.by_status(
          classroom_without_calendar.id,
          teacher.id,
          ConceptualExamStatus::INCOMPLETE
        )
      ).to be_empty

      exam = create_exam(discipline => nil)
      exam.teacher_id = nil

      expect(exam.status(nil)).to eq(ConceptualExamStatus::COMPLETE)
      expect(ConceptualExam.new.status).to eq(ConceptualExamStatus::COMPLETE)
    end

    it 'a listagem da etapa usa o mesmo status da professora' do
      exam = create_exam(discipline => 1, physical_education => nil)
      step = exam.step
      fetcher = ConceptualExamStepOverviewFetcher.new(
        classroom: classroom,
        teacher_id: teacher.id,
        discipline: discipline
      )
      allow(fetcher).to receive(:enrolled_student_ids).and_return([student.id])

      row = fetcher.student_rows_for_step(step).find { |item| item.student.id == student.id }

      expect(row.status).to eq(ConceptualExamStatus::COMPLETE)
      expect(fetcher.counts_for_rows(fetcher.student_rows_for_step(step))[:incomplete]).to eq(0)
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
