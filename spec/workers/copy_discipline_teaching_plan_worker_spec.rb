require 'rails_helper'

RSpec.describe CopyDisciplineTeachingPlanWorker, type: :worker do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:user) { create(:user, :with_user_role_administrator) }
  let(:unity) { create(:unity) }
  let(:discipline) { create(:discipline) }
  let(:classroom) { create(:classroom, unity: unity) }
  let(:classroom_grades) { create(:classrooms_grade, classroom: classroom) }
  let(:school_term_type) { create(:school_term_type, description: 'Anual') }
  let(:school_term_type_step) { create(:school_term_type_step, school_term_type: school_term_type) }
  let(:teaching_plan) do
    create(
      :teaching_plan,
      teacher: nil,
      unity: unity,
      year: classroom.year,
      grade: classroom_grades.grade,
      school_term_type: school_term_type,
      school_term_type_step: school_term_type_step
    )
  end
  let!(:discipline_teaching_plan) do
    create(:discipline_teaching_plan, discipline: discipline, teaching_plan: teaching_plan)
  end
  let!(:destination) do
    other_unity = create(:unity)
    other_classroom = create(:classroom, unity: other_unity, year: classroom.year)
    create(:classrooms_grade, classroom: other_classroom, grade: classroom_grades.grade)
    other_unity
  end

  around(:each) do |example|
    entity.using_connection { example.run }
  end

  before do
    allow(SystemNotificationCreator).to receive(:create!)
  end

  it 'records the user in the audit of created teaching plans' do
    described_class.new.perform(
      entity.id,
      user.id,
      discipline_teaching_plan.id,
      classroom.year,
      [destination.id],
      [classroom_grades.grade_id]
    )

    copied = DisciplineTeachingPlan
      .by_unity(destination.id)
      .by_year(classroom.year)
      .by_secretary
      .last

    expect(copied).to be_present
    create_audit = copied.teaching_plan.audits.where(action: 'create').order(:id).first
    expect(create_audit.user_id).to eq(user.id)
    expect(copied.teaching_plan.unificado?).to eq(true)
  end
end
