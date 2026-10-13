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

  describe 'scopes' do
    it 'filters by classroom, student and year' do
      matching = create(:aee_case_study)
      other_classroom = create(:aee_case_study, unity: matching.unity)

      expect(described_class.by_classroom(matching.classroom_id)).to eq([matching])
      expect(described_class.by_student_id(matching.student_id)).to eq([matching])
      expect(described_class.by_year(matching.year)).to include(matching)
      expect(described_class.by_classroom(other_classroom.classroom_id)).not_to include(matching)
    end
  end

  describe '.age_label_for' do
    it 'returns the age in years' do
      birth_date = Date.current - 6.years - 1.month

      expect(described_class.age_label_for(birth_date)).to eq('6 anos')
    end

    it 'returns the singular label for one year' do
      birth_date = Date.current - 1.year - 1.month

      expect(described_class.age_label_for(birth_date)).to eq('1 ano')
    end

    it 'does not count the current year before the birthday' do
      birth_date = Date.current - 6.years + 1.month

      expect(described_class.age_label_for(birth_date)).to eq('5 anos')
    end

    it 'returns nil when birth date is blank' do
      expect(described_class.age_label_for(nil)).to be_nil
    end
  end

  describe '#apply_age!' do
    it 'fills age from the student birth date' do
      student = create(:student, birth_date: Date.current - 11.years - 2.months)
      record = build(:aee_case_study, student: student, age: nil)

      record.apply_age!

      expect(record.age).to eq('11 anos')
    end
  end

  describe '#apply_identification_default!' do
    it 'fills unique deficiency names and does not overwrite an existing value' do
      student = create(:student)
      deficiency = create(:deficiency, name: 'Deficiência intelectual')
      create(:deficiency_student, student: student, deficiency: deficiency)
      create(:deficiency_student, student: student, deficiency: deficiency)

      record = build(:aee_case_study, student: student, identification: nil)
      record.apply_identification_default!

      expect(record.identification).to eq('Deficiência intelectual')

      record.identification = 'Texto ajustado pelo professor'
      record.apply_identification_default!

      expect(record.identification).to eq('Texto ajustado pelo professor')
    end
  end

  describe '#apply_regular_enrollment_fields!' do
    let(:year) { Date.current.year }
    let(:student) { create(:student) }

    it 'fills grade and modality from the regular enrollment in the same year' do
      create_aee_enrollment(student, year)
      create_regular_enrollment(student, year, grade: '3º Ano', course: 'Ensino Fundamental')

      record = build(
        :aee_case_study,
        student: student,
        year: year,
        grade_stage: 'AEE',
        modality: 'Atendimento Educacional Especializado'
      )
      record.apply_regular_enrollment_fields!

      expect(record.grade_stage).to eq('3º Ano')
      expect(record.modality).to eq('Ensino Fundamental')
    end

    it 'ignores AEE classroom and grade even when they are the current classroom' do
      aee_classroom = create_aee_enrollment(student, year)

      record = build(
        :aee_case_study,
        student: student,
        classroom: aee_classroom,
        year: year,
        grade_stage: nil,
        modality: nil
      )
      record.apply_regular_enrollment_fields!

      expect(record.grade_stage).to be_nil
      expect(record.modality).to be_nil
    end

    it 'prefers the enrollment that is still active in the classroom' do
      create_regular_enrollment(
        student,
        year,
        grade: '2º Ano',
        course: 'Ensino Fundamental',
        left_at: "#{year}-06-30"
      )
      create_regular_enrollment(student, year, grade: '3º Ano', course: 'Ensino Fundamental')

      record = build(:aee_case_study, student: student, year: year, grade_stage: nil, modality: nil)
      record.apply_regular_enrollment_fields!

      expect(record.grade_stage).to eq('3º Ano')
    end
  end

  describe '#apply_student_defaults!' do
    it 'fills age, identification, grade and modality together' do
      year = Date.current.year
      student = create(:student, birth_date: Date.current - 8.years - 1.month)
      deficiency = create(:deficiency, name: 'Transtorno do espectro autista')
      create(:deficiency_student, student: student, deficiency: deficiency)
      create_regular_enrollment(student, year, grade: '2º Ano', course: 'Ensino Fundamental')

      record = build(
        :aee_case_study,
        student: student,
        year: year,
        age: nil,
        identification: nil,
        grade_stage: nil,
        modality: nil
      )
      record.apply_student_defaults!

      expect(record.age).to eq('8 anos')
      expect(record.identification).to eq('Transtorno do espectro autista')
      expect(record.grade_stage).to eq('2º Ano')
      expect(record.modality).to eq('Ensino Fundamental')
    end
  end

  describe '#location_and_date' do
    it 'joins city, state and the document date' do
      unity = create(:unity)
      create(:address, source: unity, city: 'Maceió', state: 'AL')
      record = build(:aee_case_study, unity: unity, document_date: Date.new(2026, 8, 21))

      expect(record.location_and_date).to include('Maceió')
      expect(record.location_and_date).to include('AL')
      expect(record.location_and_date).to include(I18n.l(Date.new(2026, 8, 21), format: :long))
    end
  end

  def create_regular_enrollment(student, year, grade:, course:, left_at: '')
    regular_course = create(:course, description: course)
    regular_grade = create(:grade, course: regular_course, description: grade)
    regular_classroom = create(:classroom, year: year, description: "#{grade} A")
    classrooms_grade = create(:classrooms_grade, classroom: regular_classroom, grade: regular_grade)
    enrollment = create(:student_enrollment, student: student)
    create(
      :student_enrollment_classroom,
      student_enrollment: enrollment,
      classrooms_grade: classrooms_grade,
      left_at: left_at
    )
  end

  def create_aee_enrollment(student, year)
    aee_course = create(:course, description: 'Atendimento Educacional Especializado')
    aee_grade = create(:grade, course: aee_course, description: 'AEE')
    aee_classroom = create(:classroom, year: year, description: 'Turma AEE')
    classrooms_grade = create(:classrooms_grade, classroom: aee_classroom, grade: aee_grade)
    enrollment = create(:student_enrollment, student: student)
    create(
      :student_enrollment_classroom,
      student_enrollment: enrollment,
      classrooms_grade: classrooms_grade
    )
    aee_classroom
  end
end
