require 'rails_helper'

RSpec.describe ContentsForKnowledgeAreaRecordFetcher do
  let(:teacher) { create(:teacher) }
  let(:knowledge_area) { create(:knowledge_area) }
  let(:discipline) { create(:discipline, knowledge_area: knowledge_area) }
  let(:school_term_type) { create(:school_term_type, description: 'Anual') }
  let(:school_term_type_step) { create(:school_term_type_step) }
  let(:classroom) { create(:classroom, :with_classroom_semester_steps) }
  let(:classrooms_grade) { create(:classrooms_grade, classroom: classroom) }
  let(:teacher_discipline_classroom) {
    create(
      :teacher_discipline_classroom,
      discipline: discipline,
      teacher: teacher,
      classroom: classroom,
      grade: classrooms_grade.grade
    )
  }

  before do
    teacher_discipline_classroom
    allow_any_instance_of(TeachingPlan).to receive(:yearly?).and_return(true)
  end

  it 'does not fetch contents from a non-unificado plan of another classroom' do
    date = classroom.calendar.classroom_steps.first.first_school_calendar_date
    other_teacher = create(:teacher)
    teacher_user = create(:user, :with_user_role_teacher)
    other_classroom = create(
      :classroom,
      :with_classroom_semester_steps,
      unity: classroom.unity,
      year: classroom.year
    )
    create(:classrooms_grade, classroom: other_classroom, grade: classrooms_grade.grade)
    create(
      :teacher_discipline_classroom,
      discipline: discipline,
      teacher: other_teacher,
      classroom: other_classroom,
      grade: classrooms_grade.grade,
      year: classroom.calendar.school_calendar.year
    )

    teaching_plan = nil
    Audited.audit_class.as_user(teacher_user) do
      teaching_plan = create(
        :teaching_plan,
        school_term_type: school_term_type,
        school_term_type_step: school_term_type_step,
        grade: classrooms_grade.grade,
        teacher: other_teacher,
        year: classroom.calendar.school_calendar.year,
        unity: classroom.unity
      )
    end
    knowledge_area_teaching_plan = build(:knowledge_area_teaching_plan, teaching_plan: teaching_plan)
    knowledge_area_teaching_plan.knowledge_area_ids = [knowledge_area.id]
    knowledge_area_teaching_plan.save!

    subject = described_class.new(teacher, classroom, [knowledge_area], date)

    expect(subject.fetch).to be_empty
    expect(subject.fetch_objectives).to be_empty
  end

  it 'fetches contents from a non-unificado plan of another teacher in the same classroom' do
    date = classroom.calendar.classroom_steps.first.first_school_calendar_date
    other_teacher = create(:teacher)
    teacher_user = create(:user, :with_user_role_teacher)
    create(
      :teacher_discipline_classroom,
      discipline: discipline,
      teacher: other_teacher,
      classroom: classroom,
      grade: classrooms_grade.grade,
      year: classroom.calendar.school_calendar.year
    )

    teaching_plan = nil
    Audited.audit_class.as_user(teacher_user) do
      teaching_plan = create(
        :teaching_plan,
        school_term_type: school_term_type,
        school_term_type_step: school_term_type_step,
        grade: classrooms_grade.grade,
        teacher: other_teacher,
        year: classroom.calendar.school_calendar.year,
        unity: classroom.unity
      )
    end
    knowledge_area_teaching_plan = build(:knowledge_area_teaching_plan, teaching_plan: teaching_plan)
    knowledge_area_teaching_plan.knowledge_area_ids = [knowledge_area.id]
    knowledge_area_teaching_plan.save!

    subject = described_class.new(teacher, classroom, [knowledge_area], date)

    expect(subject.fetch).to match_array teaching_plan.contents
    expect(subject.fetch_objectives).to match_array teaching_plan.objectives
  end

  it 'fetches contents from an unificado plan of another classroom' do
    date = classroom.calendar.classroom_steps.first.first_school_calendar_date
    other_teacher = create(:teacher)
    teacher_user = create(:user, :with_user_role_teacher)
    other_classroom = create(
      :classroom,
      :with_classroom_semester_steps,
      unity: classroom.unity,
      year: classroom.year
    )
    create(:classrooms_grade, classroom: other_classroom, grade: classrooms_grade.grade)

    teaching_plan = nil
    Audited.audit_class.as_user(teacher_user) do
      teaching_plan = create(
        :teaching_plan,
        :unificado,
        school_term_type: school_term_type,
        school_term_type_step: school_term_type_step,
        grade: classrooms_grade.grade,
        teacher: other_teacher,
        year: classroom.calendar.school_calendar.year,
        unity: classroom.unity
      )
    end
    knowledge_area_teaching_plan = build(:knowledge_area_teaching_plan, teaching_plan: teaching_plan)
    knowledge_area_teaching_plan.knowledge_area_ids = [knowledge_area.id]
    knowledge_area_teaching_plan.save!

    subject = described_class.new(teacher, classroom, [knowledge_area], date)

    expect(subject.fetch).to match_array teaching_plan.contents
    expect(subject.fetch_objectives).to match_array teaching_plan.objectives
  end
end
