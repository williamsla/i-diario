class DisciplineContentRecordReport < BaseReport
  def self.build(entity_configuration, unity, date_start, date_end, discipline_content_record, current_teacher, classroom)
    new.build(entity_configuration, unity, date_start, date_end, discipline_content_record, current_teacher, classroom)
  end

  def build(entity_configuration, unity, date_start, date_end, discipline_content_record, current_teacher, classroom)

    @entity_configuration = entity_configuration
    @unity = unity
    @date_start = date_start
    @date_end = date_end
    @discipline_content_record = discipline_content_record
    @current_teacher = current_teacher
    @classroom = classroom
    attributes

    header
    body
    footer

    self
  end

  private

  def header
    entity_name = @entity_configuration ? @entity_configuration.entity_name : ''
    organ_name = @entity_configuration ? @entity_configuration.organ_name : ''
    title =  'Registros de conteúdos por disciplina - Registro diário de conteúdo'

    header_cell = make_cell(
      content: title,
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 2
    )

    begin
      entity_logo_cell = make_cell(
        image: entity_logo_io,
        fit: [50, 50],
        width: 70,
        rowspan: 4,
        position: :center,
        vposition: :center
      )
    rescue
      entity_logo_cell = make_cell(content: '', width: 70, rowspan: 4)
    end

    entity_organ_and_unity_cell = make_cell(
      content: "#{entity_name}\n#{organ_name}\n" + "#{@unity.name}",
      size: 12,
      leading: 1.5,
      align: :center,
      valign: :center,
      rowspan: 4,
      padding: [6, 0, 8, 0]
    )

    table_data = [
      [header_cell],
      [
        entity_logo_cell,
        entity_organ_and_unity_cell
      ]
    ]

    page_header do
      table(table_data, width: bounds.width) do
        cells.border_width = 0.25
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end
    end
  end

  def attributes
    # @identification_header_cell = make_cell(
    #   content: 'Identificação',
    #   size: 12,
    #   font_style: :bold,
    #   background_color: 'DEDEDE',
    #   height: 20,
    #   padding: [2, 2, 4, 4],
    #   align: :center,
    #   colspan: 2
    # )

    # @general_information_header_cell = make_cell(
    #   content: 'Informações gerais',
    #   size: 12,
    #   font_style: :bold,
    #   background_color: 'DEDEDE',
    #   height: 20,
    #   padding: [2, 2, 4, 4],
    #   align: :center,
    #   colspan: 5
    # )

    @teacher_header = make_cell(content: 'Professor', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    @unity_header = make_cell(content: 'Unidade', size: 8, font_style: :bold, borders: [:left, :right, :top], padding: [2, 2, 4, 4], colspan: 2)
    @discipline_header = make_cell(content: 'Disciplina', size: 8, font_style: :bold, borders: [:left, :right, :top], padding: [2, 2, 4, 4])
    @date_header = make_cell(content: 'Data', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', width: 23, padding: [2, 2, 4, 4])
    @class_number_header = make_cell(content: 'Aulas', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', width: 27, padding: [2, 2, 4, 4])
    @classroom_header = make_cell(content: 'Turma', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    @conteudo_header = make_cell(content: Translator.t('activerecord.attributes.discipline_content_record.contents'), size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    @habilidade_header = make_cell(content: 'Habilidade', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4], colspan: 2)
    if @display_daily_activies_log
      @daily_acitivies_header = make_cell(content: 'Práticas pedagógicas', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    end    
    @period_header = make_cell(content: 'Período', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    
    @unity_cell = make_cell(content:  @unity.name, borders: [:bottom, :left, :right], size: 10, width: 240, align: :left, padding: [0, 2, 4, 4], colspan: 2)
    @discipline_cell = make_cell(content: @discipline_content_record.first.discipline.to_s, borders: [:bottom, :left, :right], size: 10, align: :left, padding: [0, 2, 4, 4])
    @classroom_cell = make_cell(content: @classroom.description, borders: [:bottom, :left, :right], size: 10, align: :left, padding: [0, 2, 4, 4])
    @teacher_cell = make_cell(content: @current_teacher.name, borders: [:bottom, :left, :right], size: 10, align: :left, padding: [0, 2, 4, 4])
    @period_cell = make_cell(content: (@date_start == '' || @date_end == '' ? '-' : "#{@date_start} a #{@date_end}"), borders: [:bottom, :left, :right], size: 10, align: :left, padding: [0, 2, 4, 4])
  end

  def identification
    identification_table_data = [
      [@discipline_header, @classroom_header],
      [@discipline_cell, @classroom_cell],
      [@teacher_header, @period_header],
      [@teacher_cell, @period_cell]
    ]

    table(identification_table_data, width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    move_down GAP
  end

  def general_information
    general_records, individual_records = partitioned_content_records

    render_records_section('Registros gerais', general_records) if general_records.any?
    render_individual_records_section(individual_records) if individual_records.any?
  end

  def partitioned_content_records
    records = @discipline_content_record.to_a
    general_records = records.select { |record| record.content_record.student_id.blank? }
    individual_records = records.select { |record| record.content_record.student_id.present? }

    [general_records, individual_records]
  end

  def render_individual_records_section(individual_records)
    section_colspan = records_table_colspan
    section_header_cell = make_cell(
      content: 'Registros individuais',
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: section_colspan
    )

    move_down GAP
    start_new_page if cursor < 80

    table([[section_header_cell]], width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    grouped_by_student(individual_records).each do |student, records|
      render_student_group_header(student, section_colspan)
      render_records_table(records)
      render_registered_days_count(records)
    end
  end

  def grouped_by_student(individual_records)
    individual_records
      .group_by { |record| record.content_record.student }
      .sort_by { |student, _records| student.display_name.to_s }
  end

  def render_student_group_header(student, colspan)
    student_header_cell = make_cell(
      content: "Aluno: #{student}",
      size: 10,
      font_style: :bold,
      background_color: 'EEEEEE',
      padding: [4, 2, 4, 4],
      colspan: colspan
    )

    start_new_page if cursor < 60

    table([[student_header_cell]], width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end
  end

  def render_records_section(title, records)
    section_header_cell = make_cell(
      content: title,
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: records_table_colspan
    )

    table([[section_header_cell]], width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

    render_records_table(records)
    render_registered_days_count(records)
  end

  def render_registered_days_count(records)
    days_count = records.map { |record| record.content_record.record_date }.uniq.size

    move_down 4
    text("Dias registrados: #{days_count}", size: 9, style: :bold, align: :right)
    move_down GAP
  end

  def records_table_colspan
    @display_daily_activies_log ? 5 : 4
  end

  def render_records_table(records)
    headers = [
      make_cell(content: 'Data', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', width: 23, padding: [2, 2, 4, 4]),
      make_cell(content: 'Aulas', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', width: 27, padding: [2, 2, 4, 4]),
      make_cell(content: Translator.t('activerecord.attributes.discipline_content_record.contents'), size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    ]

    if @display_daily_activies_log
      headers << make_cell(content: 'Práticas pedagógicas', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    end

    headers << make_cell(content: 'Habilidade', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4], colspan: 2)

    table_data = [headers] + records.map { |record| content_record_row(record) }

    table(table_data, row_colors: ['DEDEDE', 'FFFFFF'], width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end
  end

  def content_record_row(discipline_content_record)
    content_record = discipline_content_record.content_record
    date_cell = make_cell(content: content_record.record_date.strftime('%d/%m'), size: 8, align: :left, width: 30)

    begin
      class_number = make_cell(content: discipline_content_record.class_number.to_s, size: 8, align: :center)
    rescue
      class_number = make_cell(content: '-', size: 8, align: :center)
    end

    texto_praticas_pedagogicas_e_habilidades = [
      content_record.daily_activities_record.to_s.gsub("\n", ' ').squeeze(' '),
      objective_cell_content(content_record)
    ].join("\n")

    content_cell = make_cell(content: content_cell_content(content_record), size: 8, align: :left, colspan: 1, width: 150)
    habilidade_cell = make_cell(content: texto_praticas_pedagogicas_e_habilidades, size: 7, align: :left, colspan: 3)

    [
      date_cell,
      class_number,
      content_cell,
      habilidade_cell
    ]
  end

  def body
    page_content do
      identification
      general_information
      signatures
    end
  end

  def content_cell_content(content_record)
    content_record.contents_ordered.map(&:to_s).join(', ')
  end

  def objective_cell_content(content_record)
    begin
      content_record.objectives_ordered.map(&:to_s).join("\n")
    rescue
      ''
    end
  end

  def signatures
    start_new_page if cursor < 55

    move_down 5
    begin
      total_aulas = @discipline_content_record.to_a.sum { |record| record.class_number.to_i }
      text_box("Total de aulas dadas: #{total_aulas}", size: 12, align: :left, at: [0, cursor], width: 260)
    rescue
      total_aulas = @discipline_content_record.count
      text_box("Total de aulas dadas: #{total_aulas}", size: 12, align: :left, at: [0, cursor], width: 260)
    end

    move_down 30
    text_box("______________________________________________\nProfessor(a)", size: 10, align: :center, at: [0, cursor], width: 260)
    text_box("______________________________________________\nCoordenador(a)", size: 10, align: :center, at: [306, cursor], width: 260)
  end
end
