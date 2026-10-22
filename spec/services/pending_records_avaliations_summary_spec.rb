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
  end

  it 'não trata área de conhecimento como componente opcional' do
    record = records.find { |item| item[:discipline_id].nil? }

    expect(record[:notes_required]).to eq(true)
    expect(record).not_to have_key(:students_without_note_count)
  end
end
