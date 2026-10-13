require 'rails_helper'

RSpec.describe PendingRecordsCalculator, type: :service do
  subject(:calculator) { described_class.new(school_year: 2026) }

  describe '#discarded_at_as_local_date' do
    it 'keeps the Brasília calendar day when discarded_at is end_of_day stored in UTC' do
      discarded_at = Time.find_zone('Brasilia').local(2026, 7, 27).end_of_day.utc

      expect(discarded_at.to_date).to eq(Date.new(2026, 7, 28))
      expect(calculator.send(:discarded_at_as_local_date, discarded_at)).to eq(Date.new(2026, 7, 27))
    end
  end

  describe '#lessons_board_archive_date' do
    let(:classroom) { create(:classroom, year: 2026) }
    let(:classrooms_grade) { create(:classrooms_grade, classroom: classroom) }
    let(:lessons_board) { create(:lessons_board, classrooms_grade: classrooms_grade) }

    it 'uses the informed archive date, not the following UTC day' do
      archive_until = Date.new(2026, 7, 27)
      lessons_board.update_column(:discarded_at, archive_until.end_of_day)
      allow(calculator).to receive(:effective_archived_since).and_return(nil)

      expect(calculator.send(:lessons_board_archive_date, classroom.id)).to eq(archive_until)
    end
  end

  describe '#school_days_by_board_archive_date' do
    before do
      allow(calculator).to receive(:get_equivalent_weekday_number) { |date| date.wday }
    end

    it 'uses only the current board weekdays after the archive date' do
      monday = Date.new(2026, 7, 27)
      tuesday = Date.new(2026, 7, 28)
      wednesday = Date.new(2026, 7, 29)
      active_weekdays = [wednesday.wday]
      archived_weekdays = [tuesday.wday]

      result = calculator.send(
        :school_days_by_board_archive_date,
        [monday, tuesday, wednesday],
        active_weekdays,
        archived_weekdays,
        monday
      )

      expect(result).to eq([wednesday])
    end
  end
end
