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

    it 'does not allow review date before start date' do
      subject.start_on = Date.current
      subject.review_on = Date.current - 1.day

      expect(subject).not_to be_valid
      expect(subject.errors[:review_on]).to be_present
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
