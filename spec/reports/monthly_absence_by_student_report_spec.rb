require 'rails_helper'

RSpec.describe MonthlyAbsenceByStudentReport, type: :report do
  it 'prints the presence percentage for each month and the total' do
    entity_configuration = create(:entity_configuration)
    allow(entity_configuration).to receive_message_chain(:logo, :url).and_raise(StandardError)

    row = MonthlyAbsenceByStudentFetcher::Row.new(
      'Escola',
      'Turma A',
      'Ana Silva',
      { 2 => 1, 3 => 2 },
      { 2 => 10, 3 => 8 }
    )
    unity = instance_double(Unity, name: 'Escola Municipal')
    form = instance_double(
      MonthlyAbsenceByStudentReportForm,
      rows: [row],
      parsed_months: [2, 3],
      parsed_year: 2026,
      unity: unity
    )
    allow(form).to receive(:month_label).with(2).and_return('FEVEREIRO')
    allow(form).to receive(:month_label).with(3).and_return('MARCO')

    rendered_pdf = described_class.build(entity_configuration, form).render
    content = PDF::Inspector::Text.analyze(rendered_pdf).strings.join(' ')

    expect(content).to include('1 (90,0%)')
    expect(content).to include('2 (75,0%)')
    expect(content).to include('3 (83,3%)')
  end
end
