require 'rails_helper'

RSpec.describe AbsenceJustificationRelease, type: :service do
  let(:frequency_date) { Date.current }

  def build_justification(absence_date_end: frequency_date, class_number: nil)
    create(
      :absence_justification,
      absence_date: frequency_date,
      absence_date_end: absence_date_end,
      class_number: class_number
    )
  end

  it 'remove a justificativa de um único dia e aula' do
    justification = build_justification(class_number: 2)
    link = justification.absence_justifications_students.first

    removed = described_class.call(
      absence_justifications_student_id: link.id,
      frequency_date: frequency_date,
      class_number: 2
    )

    expect(removed).to eq(true)
    expect(AbsenceJustification.find_by(id: justification.id)).to be_nil
  end

  it 'mantém a justificativa quando o período cobre mais de um dia' do
    justification = build_justification(absence_date_end: frequency_date + 1.day, class_number: 1)
    link = justification.absence_justifications_students.first

    removed = described_class.call(
      absence_justifications_student_id: link.id,
      frequency_date: frequency_date,
      class_number: 1
    )

    expect(removed).to eq(false)
    expect(AbsenceJustification.find_by(id: justification.id)).to eq(justification)
  end

  it 'mantém a justificativa de todas as aulas ao alterar só uma aula' do
    justification = build_justification(class_number: nil)
    link = justification.absence_justifications_students.first

    removed = described_class.call(
      absence_justifications_student_id: link.id,
      frequency_date: frequency_date,
      class_number: 1
    )

    expect(removed).to eq(false)
    expect(AbsenceJustification.find_by(id: justification.id)).to eq(justification)
  end

  it 'remove só o aluno quando a justificativa do dia tem outros alunos' do
    justification = build_justification(class_number: 1)
    link = justification.absence_justifications_students.first
    other_link = create(:absence_justifications_student, absence_justification: justification)

    removed = described_class.call(
      absence_justifications_student_id: link.id,
      frequency_date: frequency_date,
      class_number: 1
    )

    expect(removed).to eq(true)
    expect(AbsenceJustification.find_by(id: justification.id)).to eq(justification)
    expect(AbsenceJustificationsStudent.find_by(id: link.id)).to be_nil
    expect(AbsenceJustificationsStudent.find_by(id: other_link.id)).to eq(other_link)
  end
end
