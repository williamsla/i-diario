require 'rails_helper'

RSpec.describe AeeIndividualPlan do
  subject { build(:aee_individual_plan) }

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
    it { expect(subject).to validate_presence_of(:start_on) }
    it { expect(subject).to validate_presence_of(:document_date) }
    it { expect(subject).to validate_presence_of(:characteristics) }
    it { expect(subject).to validate_presence_of(:identified_difficulties) }
    it { expect(subject).to validate_presence_of(:goals) }
    it { expect(subject).to validate_presence_of(:psychomotor_skills) }
    it { expect(subject).to validate_presence_of(:cognitive_skills) }
    it { expect(subject).to validate_presence_of(:socioemotional_skills) }
    it { expect(subject).to validate_presence_of(:linguistic_skills) }

    it 'does not allow a second PEI for the same student, classroom and year' do
      existing = create(:aee_individual_plan)
      duplicate = build(
        :aee_individual_plan,
        classroom: existing.classroom,
        student: existing.student,
        year: existing.year,
        unity: existing.unity,
        school_calendar: existing.school_calendar
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:student_id]).to be_present
    end

    it 'allows several linked disciplines on the same regular PEI and one PEI per teacher' do
      existing = create(:aee_individual_plan, :regular)
      extra = create(:discipline)
      create(
        :teacher_discipline_classroom,
        teacher: existing.teacher,
        classroom: existing.classroom,
        discipline: extra,
        year: existing.year
      )
      existing.discipline_ids = existing.discipline_ids + [extra.id]

      another_teacher = build(
        :aee_individual_plan,
        :regular,
        classroom: existing.classroom,
        student: existing.student,
        year: existing.year,
        unity: existing.unity,
        school_calendar: existing.school_calendar
      )
      duplicate = build(
        :aee_individual_plan,
        :regular,
        classroom: existing.classroom,
        student: existing.student,
        year: existing.year,
        unity: existing.unity,
        school_calendar: existing.school_calendar,
        teacher: existing.teacher
      )
      duplicate.discipline_ids = existing.discipline_ids

      expect(existing).to be_valid
      expect(another_teacher).to be_valid
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:student_id]).to be_present
    end

    it 'requires a linked discipline on a regular PEI and removes disciplines from an AEE PEI' do
      regular_pei = build(:aee_individual_plan, :regular)
      regular_pei.disciplines = []
      aee_pei = build(:aee_individual_plan)
      aee_pei.disciplines = [create(:discipline)]
      unlinked = create(:aee_individual_plan, :regular)
      unlinked.discipline_ids = [create(:discipline).id]

      expect(regular_pei).not_to be_valid
      expect(regular_pei.errors[:disciplines]).to be_present
      expect(aee_pei).to be_valid
      expect(aee_pei.discipline_ids).to be_empty
      expect(unlinked).not_to be_valid
      expect(unlinked.errors[:disciplines]).to be_present
    end

    it 'does not allow review date before start date' do
      subject.start_on = Date.current
      subject.review_on = Date.current - 1.day

      expect(subject).not_to be_valid
      expect(subject.errors[:review_on]).to be_present
    end
  end

  describe 'visibility and ownership' do
    let(:unity) { create(:unity) }
    let(:year) { Date.current.year }
    let(:regular_classroom) { create(:classroom, unity: unity, year: year) }
    let(:other_classroom) { create(:classroom, unity: unity, year: year) }
    let(:aee_classroom) { create(:classroom, unity: unity, year: year) }
    let(:portuguese) { create(:discipline) }
    let(:math) { create(:discipline) }
    let(:student) { create(:student, uses_differentiated_exam_rule: true) }
    let(:other_student) { create(:student, uses_differentiated_exam_rule: true) }
    let(:school_calendar) { create(:school_calendar, :with_one_step, unity: unity) }
    let(:regular_user) do
      instance_double(
        User,
        classroom: regular_classroom,
        discipline: portuguese,
        current_school_year: year,
        current_unity_id: unity.id,
        current_teacher: portuguese_pei.teacher
      )
    end

    let!(:portuguese_pei) do
      create(
        :aee_individual_plan,
        :regular,
        unity: unity,
        classroom: regular_classroom,
        student: student,
        year: year,
        school_calendar: school_calendar
      )
    end
    let!(:math_pei) do
      create(
        :aee_individual_plan,
        :regular,
        unity: unity,
        classroom: regular_classroom,
        student: student,
        year: year,
        school_calendar: school_calendar
      )
    end
    let!(:other_class_pei) do
      create(
        :aee_individual_plan,
        :regular,
        unity: unity,
        classroom: other_classroom,
        student: student,
        year: year,
        school_calendar: school_calendar
      )
    end
    let!(:aee_pei) do
      create(
        :aee_individual_plan,
        unity: unity,
        classroom: aee_classroom,
        student: student,
        year: year,
        school_calendar: school_calendar
      )
    end
    let!(:other_student_pei) do
      create(
        :aee_individual_plan,
        :regular,
        unity: unity,
        classroom: regular_classroom,
        student: other_student,
        year: year,
        school_calendar: school_calendar
      )
    end

    before do
      allow(regular_classroom).to receive(:aee?).and_return(false)
      allow(other_classroom).to receive(:aee?).and_return(false)
      allow(aee_classroom).to receive(:aee?).and_return(true)
      allow(described_class).to receive(:linked_disciplines_for).and_return([portuguese])
      allow(StudentEnrollmentsList).to receive(:new).and_return(
        instance_double(
          StudentEnrollmentsList,
          student_enrollments: [instance_double(StudentEnrollment, student_id: student.id)]
        )
      )
    end

    it 'lists the regular PEIs of the classroom and the AEE PEI of the student' do
      visible_ids = described_class.visible_for(regular_user).pluck(:id)

      expect(visible_ids).to include(portuguese_pei.id, math_pei.id, aee_pei.id)
      expect(visible_ids).not_to include(other_class_pei.id, other_student_pei.id)
    end

    it 'allows the teacher to edit only the PEI they own' do
      expect(portuguese_pei.owned_by?(regular_user)).to eq(true)
      expect(math_pei.owned_by?(regular_user)).to eq(false)
      expect(aee_pei.owned_by?(regular_user)).to eq(false)
    end

    it 'shows every PEI of the student to the AEE teacher and keeps edit on the AEE record' do
      aee_user = instance_double(
        User,
        classroom: aee_classroom,
        discipline: nil,
        current_school_year: year,
        current_unity_id: unity.id
      )
      visible_ids = described_class.visible_for(aee_user).pluck(:id)

      expect(visible_ids).to include(portuguese_pei.id, math_pei.id, other_class_pei.id, aee_pei.id)
      expect(visible_ids).not_to include(other_student_pei.id)
      expect(aee_pei.owned_by?(aee_user)).to eq(true)
      expect(portuguese_pei.owned_by?(aee_user)).to eq(false)
    end
  end

  describe '#attendance_records' do
    it 'returns no records when there are no attendances for the student' do
      pei = create(:aee_individual_plan)

      expect(pei.attendance_records).to be_empty
    end
  end

  describe '#apply_defaults!' do
    it 'prefers PAEE planning fields over the case study' do
      pei = build(
        :aee_individual_plan,
        characteristics: nil,
        identified_difficulties: nil,
        goals: nil,
        resources: nil,
        strategies: nil,
        monitoring: nil,
        cognitive_skills: nil
      )
      case_study = create(
        :aee_case_study,
        student: pei.student,
        classroom: pei.classroom,
        unity: pei.unity,
        year: pei.year,
        school_calendar: pei.school_calendar
      )
      teaching_plan = create(
        :teaching_plan,
        student: pei.student,
        year: pei.year,
        methodology: '<p>Estratégia PAEE</p>',
        evaluation: '<p>Avaliação PAEE</p>'
      )
      teaching_plan.create_aee_teaching_plan_detail!(
        student_characteristics: 'Características PAEE',
        general_objectives: 'Objetivos PAEE',
        resources: 'Recursos PAEE',
        cognitive_objectives: 'Cognição PAEE'
      )

      pei.apply_defaults!

      expect(pei.aee_case_study).to eq(case_study)
      expect(pei.identified_difficulties).to include(case_study.individual_demands)
      expect(pei.characteristics).to eq('Características PAEE')
      expect(pei.goals).to eq('Objetivos PAEE')
      expect(pei.resources).to eq('Recursos PAEE')
      expect(pei.strategies).to eq('Estratégia PAEE')
      expect(pei.monitoring).to eq('Avaliação PAEE')
      expect(pei.cognitive_skills).to eq('Cognição PAEE')
    end
  end
end
