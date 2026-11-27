require 'rails_helper'

RSpec.describe PendingRecordsCalculator, type: :service do
  describe '#process_infantil_classroom' do
    let(:today) { Date.current.beginning_of_week(:monday) }
    let(:last_monday) { today - 7.days }
    let(:knowledge_area) { create(:knowledge_area, description: 'Campos de experiência') }
    let(:discipline) { create(:discipline, knowledge_area: knowledge_area, description: 'Campos de experiência') }
    let(:morning_teacher) { create(:teacher) }
    let(:afternoon_teacher) { create(:teacher) }
    let(:calculator) { described_class.new(school_year: classroom.year) }

    let(:classroom) do
      create(:classroom, year: Date.current.year, period: Periods::FULL)
    end
    let!(:classrooms_grade) { create(:classrooms_grade, classroom: classroom) }
    let(:grade) { classrooms_grade.grade }

    before do
      allow(calculator).to receive(:get_equivalent_weekday_number) { |date| date.wday }
      allow(calculator).to receive(:filter_saturdays_by_events) { |dates, *_args| dates }
      allow(calculator).to receive(:apply_optional_holidays!).and_return(Set.new)
      allow(calculator).to receive(:lessons_board_archive_date).and_return(nil)
    end

    def link_teacher(teacher, period, active: true)
      create(
        :teacher_discipline_classroom,
        teacher: teacher,
        classroom: classroom,
        discipline: discipline,
        grade: grade,
        year: classroom.year,
        period: period.to_i,
        active: active
      )
    end

    def add_monday(teacher_discipline_classroom, period)
      add_weekday(teacher_discipline_classroom, period, 'monday')
    end

    def add_weekday(teacher_discipline_classroom, period, weekday)
      board = LessonsBoard.find_by(classrooms_grade_id: classrooms_grade.id, period: period.to_i)
      board ||= create(:lessons_board, classrooms_grade: classrooms_grade, period: period.to_i)
      lesson = board.lessons_board_lessons.first
      lesson ||= create(:lessons_board_lesson, lessons_board: board, lesson_number: 1)
      create(
        :lessons_board_lesson_weekday,
        lessons_board_lesson: lesson,
        teacher_discipline_classroom: teacher_discipline_classroom,
        weekday: weekday
      )
    end

    def create_area_content(teacher, date)
      content_record = build(
        :content_record,
        :with_contents,
        classroom: classroom,
        teacher: teacher,
        record_date: date
      )
      content_record.save!(validate: false)

      record = KnowledgeAreaContentRecord.new(content_record: content_record)
      record.save!(validate: false)
      record.knowledge_areas << knowledge_area
      record
    end

    def create_general_frequency(teacher, date, period)
      DailyFrequency.new(
        classroom_id: classroom.id,
        unity_id: classroom.unity_id,
        school_calendar: create(:school_calendar, unity: classroom.unity, year: classroom.year),
        frequency_date: date,
        period: period.to_i,
        owner_teacher_id: teacher.id
      ).tap { |frequency| frequency.save!(validate: false) }
    end

    def pending_for(teacher, school_days = [last_monday, today])
      calculator.send(
        :process_infantil_classroom,
        classroom,
        [knowledge_area.id],
        nil,
        school_days.min,
        school_days.max,
        true,
        school_days,
        today,
        grade.id,
        teacher.id
      ).first
    end

    context 'quando a turma integral tem um professor em cada turno na mesma área' do
      let!(:morning_link) { link_teacher(morning_teacher, Periods::MATUTINAL) }
      let!(:afternoon_link) { link_teacher(afternoon_teacher, Periods::VESPERTINE) }

      before do
        add_monday(morning_link, Periods::MATUTINAL)
        add_monday(afternoon_link, Periods::VESPERTINE)
        create_area_content(afternoon_teacher, today)
        create_general_frequency(afternoon_teacher, today, Periods::VESPERTINE)
      end

      it 'mantém a pendência do matutino no dia que só o vespertino registrou' do
        morning = pending_for(morning_teacher)
        afternoon = pending_for(afternoon_teacher)

        expect(morning[:pending_content_dates]).to eq([last_monday, today])
        expect(morning[:pending_frequency_dates]).to eq([last_monday, today])
        expect(afternoon[:pending_content_dates]).to eq([last_monday])
        expect(afternoon[:pending_frequency_dates]).to eq([last_monday])
      end
    end

    context 'quando o professor do turno é substituído' do
      let(:predecessor) { create(:teacher) }
      let!(:predecessor_link) { link_teacher(predecessor, Periods::MATUTINAL, active: false) }
      let!(:morning_link) { link_teacher(morning_teacher, Periods::MATUTINAL) }

      before do
        add_monday(morning_link, Periods::MATUTINAL)
        create_area_content(predecessor, last_monday)
        create_general_frequency(predecessor, last_monday, Periods::MATUTINAL)
      end

      it 'não cobra do novato o dia que o professor anterior do mesmo turno já registrou' do
        pending = pending_for(morning_teacher)

        expect(pending[:pending_content_dates]).to eq([today])
        expect(pending[:pending_frequency_dates]).to eq([today])
      end
    end

    context 'quando os dois professores são do mesmo turno' do
      let(:classroom) do
        create(:classroom, year: Date.current.year, period: Periods::MATUTINAL)
      end
      let!(:morning_link) { link_teacher(morning_teacher, Periods::MATUTINAL) }
      let!(:partner_link) { link_teacher(afternoon_teacher, Periods::MATUTINAL) }

      before do
        add_monday(morning_link, Periods::MATUTINAL)
        add_monday(partner_link, Periods::MATUTINAL)
        create_area_content(morning_teacher, today)
        create_general_frequency(morning_teacher, today, Periods::MATUTINAL)
      end

      it 'considera o registro do outro professor do mesmo turno' do
        pending = pending_for(afternoon_teacher)

        expect(pending[:pending_content_dates]).to eq([last_monday])
        expect(pending[:pending_frequency_dates]).to eq([last_monday])
      end
    end

    context 'quando cada professora tem um dia diferente no mesmo turno' do
      let(:last_wednesday) { last_monday + 2.days }
      let(:school_days) { [last_monday, last_wednesday, today] }
      let(:classroom) do
        create(:classroom, year: Date.current.year, period: Periods::MATUTINAL)
      end
      let!(:morning_link) { link_teacher(morning_teacher, Periods::MATUTINAL) }
      let!(:wednesday_link) { link_teacher(afternoon_teacher, Periods::MATUTINAL) }

      before do
        add_weekday(morning_link, Periods::MATUTINAL, 'monday')
        add_weekday(wednesday_link, Periods::MATUTINAL, 'wednesday')
        create_area_content(afternoon_teacher, last_wednesday)
        create_general_frequency(afternoon_teacher, last_wednesday, Periods::MATUTINAL)
      end

      it 'cobra só o dia de cada uma no quadro' do
        monday_teacher = pending_for(morning_teacher, school_days)
        wednesday_teacher = pending_for(afternoon_teacher, school_days)

        expect(monday_teacher[:pending_content_dates]).to eq([last_monday, today])
        expect(monday_teacher[:pending_frequency_dates]).to eq([last_monday, today])
        expect(wednesday_teacher[:pending_content_dates]).to eq([])
        expect(wednesday_teacher[:pending_frequency_dates]).to eq([])
      end
    end

    context 'quando a professora não está no quadro do turno' do
      let(:last_wednesday) { last_monday + 2.days }
      let(:school_days) { [last_monday, last_wednesday, today] }
      let(:classroom) do
        create(:classroom, year: Date.current.year, period: Periods::MATUTINAL)
      end
      let!(:teacher_link) { link_teacher(morning_teacher, Periods::MATUTINAL) }
      let!(:board_link) { link_teacher(afternoon_teacher, Periods::MATUTINAL) }

      before do
        add_weekday(board_link, Periods::MATUTINAL, 'wednesday')
      end

      it 'olha a frequência nos dias da disciplina dela no quadro' do
        pending = pending_for(morning_teacher, school_days)

        expect(pending[:pending_frequency_dates]).to eq([last_wednesday])
        expect(pending[:pending_content_dates]).to eq([last_wednesday])
      end
    end

    context 'quando a substituída continua com vínculo ativo, mas saiu do quadro' do
      let(:predecessor) { create(:teacher) }
      let(:classroom) do
        create(:classroom, year: Date.current.year, period: Periods::FULL)
      end
      let!(:predecessor_link) { link_teacher(predecessor, Periods::FULL) }
      let!(:successor_link) { link_teacher(morning_teacher, Periods::FULL) }
      let!(:other_link) { link_teacher(afternoon_teacher, Periods::FULL) }
      let(:last_wednesday) { last_monday + 2.days }
      let(:school_days) { [last_monday, last_wednesday, today] }

      before do
        add_weekday(successor_link, Periods::FULL, 'monday')
        add_weekday(other_link, Periods::FULL, 'wednesday')
        create_area_content(predecessor, last_monday)
        create_general_frequency(predecessor, last_monday, Periods::FULL)
      end

      it 'passa o conteúdo dela para quem assumiu o dia' do
        successor = pending_for(morning_teacher, school_days)
        colleague = pending_for(afternoon_teacher, school_days)

        expect(successor[:pending_content_dates]).to eq([today])
        expect(successor[:pending_frequency_dates]).to eq([today])
        expect(colleague[:pending_content_dates]).to eq([last_wednesday])
        expect(colleague[:pending_frequency_dates]).to eq([last_wednesday])
      end
    end

    context 'quando a substituta do integral assume o dia de quem saiu' do
      let(:predecessor) { create(:teacher) }
      let(:classroom) do
        create(:classroom, year: Date.current.year, period: Periods::FULL)
      end
      let!(:predecessor_link) { link_teacher(predecessor, Periods::FULL, active: false) }
      let!(:successor_link) { link_teacher(morning_teacher, Periods::FULL) }
      let!(:other_link) { link_teacher(afternoon_teacher, Periods::FULL) }
      let(:last_wednesday) { last_monday + 2.days }
      let(:school_days) { [last_monday, last_wednesday, today] }

      before do
        add_weekday(successor_link, Periods::FULL, 'monday')
        add_weekday(other_link, Periods::FULL, 'wednesday')
        create_area_content(predecessor, last_monday)
        create_general_frequency(predecessor, last_monday, Periods::FULL)
      end

      it 'não cobra de novo o conteúdo da professora substituída e não puxa o dia da colega' do
        successor = pending_for(morning_teacher, school_days)
        colleague = pending_for(afternoon_teacher, school_days)

        expect(successor[:pending_content_dates]).to eq([today])
        expect(successor[:pending_frequency_dates]).to eq([today])
        expect(colleague[:pending_content_dates]).to eq([last_wednesday])
        expect(colleague[:pending_frequency_dates]).to eq([last_wednesday])
      end
    end
  end
end
