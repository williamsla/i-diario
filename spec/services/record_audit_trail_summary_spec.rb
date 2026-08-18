require 'rails_helper'

RSpec.describe RecordAuditTrailSummary, type: :service do
  let(:knowledge_area) do
    create(:knowledge_area, description: 'Educação Infantil', group_descriptors: true)
  end
  let(:grouper) do
    create(
      :discipline,
      knowledge_area: knowledge_area,
      grouper: true,
      description: 'Educação Infantil'
    )
  end
  let(:other_knowledge_area) { create(:knowledge_area, description: 'Linguagens') }
  let(:teacher) { create(:teacher) }
  let(:classroom) do
    create(
      :classroom,
      :score_type_numeric,
      :with_classroom_semester_steps
    )
  end
  let(:step) { classroom.calendar.classroom_steps.first }
  let(:record_date) { step.first_school_calendar_date }

  before do
    create(
      :teacher_discipline_classroom,
      teacher: teacher,
      classroom: classroom,
      discipline: grouper
    )
  end

  def summary(discipline_id:, record_types:)
    described_class.new(
      unity_id: classroom.unity_id,
      classroom_id: classroom.id,
      teacher_id: teacher.id,
      discipline_id: discipline_id,
      start_date: Date.new(classroom.year, 1, 1),
      end_date: Date.new(classroom.year, 12, 31),
      record_types: record_types
    ).call
  end

  describe 'quando a turma lança por área de conhecimento' do
    it 'traz conteúdo por área ao filtrar pela disciplina agrupadora' do
      content_record = create(
        :content_record,
        :with_contents,
        classroom: classroom,
        teacher: teacher,
        record_date: record_date
      )
      ka_record = create(
        :knowledge_area_content_record,
        content_record: content_record,
        knowledge_areas: [knowledge_area]
      )

      other_content_record = create(
        :content_record,
        :with_contents,
        classroom: classroom,
        teacher: teacher,
        record_date: record_date
      )
      create(
        :knowledge_area_content_record,
        content_record: other_content_record,
        knowledge_areas: [other_knowledge_area]
      )

      results = summary(discipline_id: grouper.id, record_types: ['content'])

      expect(results.map { |result| result[:auditable_id] }).to eq([ka_record.id])
      expect(results.first[:auditable_type]).to eq('KnowledgeAreaContentRecord')
    end

    it 'traz frequência geral ao filtrar pela disciplina agrupadora' do
      daily_frequency = create(
        :daily_frequency,
        :without_discipline,
        classroom: classroom,
        unity: classroom.unity,
        school_calendar: classroom.calendar.school_calendar,
        teacher: teacher,
        frequency_date: record_date
      )

      results = summary(discipline_id: grouper.id, record_types: ['frequency'])

      expect(results.map { |result| result[:auditable_id] }).to eq([daily_frequency.id])
      expect(results.first[:auditable_type]).to eq('DailyFrequency')
    end

    it 'traz plano de aula por área ao filtrar pela disciplina agrupadora' do
      lesson_plan = create(
        :lesson_plan,
        classroom: classroom,
        teacher: teacher,
        teacher_id: teacher.id
      )
      ka_lesson_plan = create(
        :knowledge_area_lesson_plan,
        lesson_plan: lesson_plan,
        knowledge_area_ids: knowledge_area.id,
        teacher_id: teacher.id
      )

      results = summary(discipline_id: grouper.id, record_types: ['lesson_plan'])

      expect(results.map { |result| result[:auditable_id] }).to eq([ka_lesson_plan.id])
      expect(results.first[:auditable_type]).to eq('KnowledgeAreaLessonPlan')
    end

    it 'traz plano de ensino por área ao filtrar pela disciplina agrupadora' do
      teaching_plan = create(
        :teaching_plan,
        unity: classroom.unity,
        teacher: teacher,
        teacher_id: teacher.id,
        grade: classroom.classrooms_grades.first.grade,
        year: classroom.year
      )
      ka_teaching_plan = create(
        :knowledge_area_teaching_plan,
        teaching_plan: teaching_plan
      )
      ka_teaching_plan.knowledge_areas << knowledge_area

      results = summary(discipline_id: grouper.id, record_types: ['teaching_plan'])

      expect(results.map { |result| result[:auditable_id] }).to eq([ka_teaching_plan.id])
      expect(results.first[:auditable_type]).to eq('KnowledgeAreaTeachingPlan')
    end
  end

  describe 'quando a disciplina não é por área de conhecimento' do
    let(:regular_discipline) { create(:discipline) }

    before do
      create(
        :teacher_discipline_classroom,
        teacher: teacher,
        classroom: classroom,
        discipline: regular_discipline
      )
    end

    it 'não traz frequência de outra disciplina' do
      create(
        :daily_frequency,
        classroom: classroom,
        unity: classroom.unity,
        school_calendar: classroom.calendar.school_calendar,
        teacher: teacher,
        discipline: create(:discipline),
        frequency_date: record_date,
        class_number: 1
      )
      matching_frequency = create(
        :daily_frequency,
        classroom: classroom,
        unity: classroom.unity,
        school_calendar: classroom.calendar.school_calendar,
        teacher: teacher,
        discipline: regular_discipline,
        frequency_date: record_date,
        class_number: 1
      )

      results = summary(discipline_id: regular_discipline.id, record_types: ['frequency'])

      expect(results.map { |result| result[:auditable_id] }).to eq([matching_frequency.id])
    end
  end
end
