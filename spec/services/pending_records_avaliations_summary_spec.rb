require 'rails_helper'

RSpec.describe PendingRecordsAvaliationsSummary, type: :service do
  let(:classroom) { create(:classroom) }
  let(:optional_discipline) { create(:discipline, disregard_for_progression: true) }
  let(:required_discipline) { create(:discipline, disregard_for_progression: false) }
  let(:start_date) { Date.current.beginning_of_year }
  let(:end_date) { Date.current }

  subject(:records) do
    described_class.new(
      classroom: classroom,
      start_date: start_date,
      end_date: end_date,
      pending_records: [
        { discipline_id: optional_discipline.id, discipline_name: optional_discipline.description },
        { discipline_id: required_discipline.id, discipline_name: required_discipline.description },
        { discipline_id: nil, knowledge_area_id: 1, discipline_name: 'Campos de experiência' }
      ]
    ).apply!
  end

  it 'não exige nota quando o componente é desconsiderado na aprovação' do
    record = records.find { |item| item[:discipline_id] == optional_discipline.id }

    expect(record[:notes_required]).to eq(false)
    expect(record).not_to have_key(:students_without_note_count)
  end

  it 'mantém a pendência de nota nos demais componentes' do
    record = records.find { |item| item[:discipline_id] == required_discipline.id }

    expect(record[:notes_required]).to eq(true)
    expect(record[:students_without_note_from_classroom_total]).to eq(true)
    expect(record[:students_without_note_status]).to eq(described_class::NOT_STARTED)
  end

  it 'não trata área de conhecimento como componente opcional' do
    record = records.find { |item| item[:discipline_id].nil? }

    expect(record[:notes_required]).to eq(true)
    expect(record).not_to have_key(:students_without_note_count)
  end

  context 'quando o município oculta o aviso' do
    before do
      allow(GeneralConfiguration).to receive(:show_optional_discipline_note_message?).and_return(false)
    end

    it 'confere o lançamento da disciplina não obrigatória como nas obrigatórias' do
      optional_record = records.find { |item| item[:discipline_id] == optional_discipline.id }
      required_record = records.find { |item| item[:discipline_id] == required_discipline.id }

      expect(optional_record[:notes_required]).to eq(false)
      expect(optional_record[:students_without_note_count]).to eq(required_record[:students_without_note_count])
      expect(optional_record[:students_without_note_from_classroom_total]).to eq(true)
      expect(optional_record[:students_without_note_status]).to eq(described_class::NOT_STARTED)
    end
  end

  context 'quando a etapa tem avaliação numérica' do
    let(:classroom) { create(:classroom, :with_classroom_semester_steps) }
    let(:discipline) { create(:discipline) }
    let(:year) { classroom.year }
    let(:test_date) { Date.new(year, 8, 10) }
    let(:start_date) { Date.new(year, 7, 1) }
    let(:end_date) { Date.new(year, 12, 31) }

    def summarize
      described_class.new(
        classroom: classroom,
        start_date: start_date,
        end_date: end_date,
        pending_records: [
          { discipline_id: discipline.id, discipline_name: discipline.description }
        ]
      ).apply!.first
    end

    def enroll_student
      classrooms_grade = create(:classrooms_grade, classroom: classroom)
      create(
        :student_enrollment_classroom,
        classrooms_grade: classrooms_grade,
        joined_at: Date.new(year, 1, 1),
        left_at: ''
      ).student_enrollment.student
    end

    def launch_avaliation(notes_by_student)
      avaliation = build(
        :avaliation,
        :with_teacher_discipline_classroom,
        classroom: classroom,
        discipline: discipline,
        test_date: test_date,
        teacher: create(:teacher)
      )
      avaliation.save!(validate: false)

      daily_note = build(:daily_note, avaliation: avaliation)
      daily_note.save!(validate: false)

      notes_by_student.each do |student, note|
        create(:daily_note_student, daily_note: daily_note, student: student, note: note, active: true)
      end
    end

    it 'marca não iniciou quando a avaliação existe e todos os alunos estão em branco' do
      student = enroll_student
      launch_avaliation(student => nil)

      record = summarize

      expect(record[:students_without_note_status]).to eq(described_class::NOT_STARTED)
      expect(record[:students_without_note_from_classroom_total]).to eq(false)
    end

    it 'marca parcial e conta os alunos ainda sem nota quando já existe nota lançada' do
      with_note = enroll_student
      without_note = enroll_student
      launch_avaliation(with_note => 8, without_note => nil)

      record = summarize

      expect(record[:students_without_note_status]).to eq(described_class::PARTIAL)
      expect(record[:students_without_note_count]).to eq(1)
    end

    it 'marca tudo certo quando todos os alunos estão com nota' do
      first_student = enroll_student
      second_student = enroll_student
      launch_avaliation(first_student => 8, second_student => 7)

      record = summarize

      expect(record[:students_without_note_status]).to eq(described_class::COMPLETE)
      expect(record[:students_without_note_count]).to eq(0)
    end
  end
end
