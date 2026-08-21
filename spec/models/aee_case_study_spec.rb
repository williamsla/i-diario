require 'rails_helper'

RSpec.describe AeeCaseStudy do
  subject { build(:aee_case_study) }

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
    it { expect(subject).to validate_presence_of(:document_date) }
    it { expect(subject).to validate_presence_of(:grade_stage) }
    it { expect(subject).to validate_presence_of(:identification) }
    it { expect(subject).to validate_presence_of(:modality) }
    it { expect(subject).to validate_presence_of(:individual_demands) }
    it { expect(subject).to validate_presence_of(:barriers_and_context) }
    it { expect(subject).to validate_presence_of(:potentialities_and_support) }
    it { expect(subject).to validate_presence_of(:accessibility_strategies) }

    it 'does not allow a second study for the same student, classroom and year' do
      existing = create(:aee_case_study)
      duplicate = build(
        :aee_case_study,
        classroom: existing.classroom,
        student: existing.student,
        year: existing.year,
        unity: existing.unity,
        school_calendar: existing.school_calendar
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:student_id]).to be_present
    end
  end

  describe '.age_label_for' do
    it 'returns the age in years' do
      birth_date = Date.current - 6.years - 1.month

      expect(described_class.age_label_for(birth_date)).to eq('6 anos')
    end

    it 'returns nil when birth date is blank' do
      expect(described_class.age_label_for(nil)).to be_nil
    end
  end

  describe '#apply_student_defaults!' do
    it 'fills grade and modality from the regular enrollment in the same year' do
      year = Date.current.year
      student = create(:student)
      enrollment = create(:student_enrollment, student: student)

      regular_course = create(:course, description: 'Ensino Fundamental')
      regular_grade = create(:grade, course: regular_course, description: '3º Ano')
      regular_classroom = create(:classroom, year: year, description: '3º Ano A')
      regular_classrooms_grade = create(:classrooms_grade, classroom: regular_classroom, grade: regular_grade)
      create(
        :student_enrollment_classroom,
        student_enrollment: enrollment,
        classrooms_grade: regular_classrooms_grade
      )

      aee_course = create(:course, description: 'Atendimento Educacional Especializado')
      aee_grade = create(:grade, course: aee_course, description: 'AEE')
      aee_classroom = create(:classroom, year: year, description: 'Turma AEE')
      aee_classrooms_grade = create(:classrooms_grade, classroom: aee_classroom, grade: aee_grade)
      create(
        :student_enrollment_classroom,
        student_enrollment: enrollment,
        classrooms_grade: aee_classrooms_grade
      )

      record = build(
        :aee_case_study,
        student: student,
        classroom: aee_classroom,
        year: year,
        grade_stage: nil,
        modality: nil
      )
      record.apply_student_defaults!

      expect(record.grade_stage).to eq('3º Ano')
      expect(record.modality).to eq('Ensino Fundamental')
    end
  end
end
