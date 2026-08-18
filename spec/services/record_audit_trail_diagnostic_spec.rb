require 'rails_helper'

RSpec.describe RecordAuditTrailDiagnostic, type: :service do
  let(:teacher) { create(:teacher) }
  let(:classroom) do
    create(
      :classroom,
      :score_type_numeric,
      :with_classroom_semester_steps
    )
  end
  let(:other_classroom) do
    create(
      :classroom,
      :score_type_numeric,
      :with_classroom_semester_steps,
      unity: classroom.unity
    )
  end
  let(:discipline) { create(:discipline, description: 'Matemática') }
  let(:other_discipline) { create(:discipline, description: 'Português') }
  let(:step) { classroom.calendar.classroom_steps.first }
  let(:record_date) { step.first_school_calendar_date }

  before do
    create(
      :teacher_discipline_classroom,
      teacher: teacher,
      classroom: classroom,
      discipline: discipline
    )
    create(
      :teacher_discipline_classroom,
      teacher: teacher,
      classroom: classroom,
      discipline: other_discipline
    )
    create(
      :teacher_discipline_classroom,
      teacher: teacher,
      classroom: other_classroom,
      discipline: discipline
    )

    allow(PendingRecordsCalculator).to receive(:new).and_return(
      instance_double(PendingRecordsCalculator, calculate: [])
    )
  end

  def diagnostic(classroom_id: classroom.id, discipline_id: discipline.id, start_date: record_date, end_date: record_date)
    described_class.new(
      unity_id: classroom.unity_id,
      classroom_id: classroom_id,
      teacher_id: teacher.id,
      discipline_id: discipline_id,
      start_date: start_date,
      end_date: end_date,
      record_types: %w[frequency content],
      school_year: classroom.year
    ).call
  end

  it 'aponta lançamento na disciplina errada como vizinho' do
    create(
      :daily_frequency,
      classroom: classroom,
      unity: classroom.unity,
      school_calendar: classroom.calendar.school_calendar,
      teacher: teacher,
      discipline: other_discipline,
      frequency_date: record_date,
      class_number: 1
    )

    result = diagnostic

    expect(result[:results]).to be_empty
    expect(result[:neighbors].size).to eq(1)
    expect(result[:neighbors].first[:mismatch_reasons]).to include('other_discipline')
    expect(result[:phrase]).to include('outra disciplina')
  end

  it 'aponta lançamento na turma errada como vizinho' do
    create(
      :daily_frequency,
      classroom: other_classroom,
      unity: classroom.unity,
      school_calendar: other_classroom.calendar.school_calendar,
      teacher: teacher,
      discipline: discipline,
      frequency_date: record_date,
      class_number: 1
    )

    result = diagnostic

    expect(result[:results]).to be_empty
    expect(result[:neighbors].first[:mismatch_reasons]).to include('other_classroom')
    expect(result[:phrase]).to include('outra turma')
  end

  it 'monta calendário com pendência de frequência' do
    allow(PendingRecordsCalculator).to receive(:new).and_return(
      instance_double(
        PendingRecordsCalculator,
        calculate: [{
          discipline_name: 'Matemática',
          pending_frequency_dates: [record_date],
          pending_content_dates: [record_date]
        }]
      )
    )

    result = diagnostic

    expect(result[:calendar].size).to eq(1)
    expect(result[:calendar].first[:frequency][:status]).to eq('missing')
    expect(result[:calendar].first[:content][:status]).to eq('missing')
    expect(result[:phrase]).to include('Não há frequência lançada')
  end

  it 'avisa quando o vínculo da professora com a turma foi encerrado' do
    TeacherDisciplineClassroom.where(teacher: teacher, classroom: classroom).find_each(&:discard)

    result = diagnostic

    expect(result[:allocation][:status]).to eq('unlinked')
    expect(result[:phrase]).to include('vínculo')
    expect(result[:phrase]).to include('encerrado')
  end
end
