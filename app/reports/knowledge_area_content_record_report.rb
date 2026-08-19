class KnowledgeAreaContentRecordReport < BaseReport
  def self.build(entity_configuration, date_start, date_end, knowledge_area_content_records, current_teacher)
    new.build(entity_configuration, date_start, date_end, knowledge_area_content_records, current_teacher)
  end

  def build(entity_configuration, date_start, date_end, knowledge_area_content_records, current_teacher)
    @entity_configuration = entity_configuration
    @date_start = date_start
    @date_end = date_end
    @knowledge_area_content_records = knowledge_area_content_records
    @current_teacher = current_teacher
    attributes

    header
    body
    footer

    self
  end

  private

  def header
    entity_name = @entity_configuration.try(:entity_name).to_s
    organ_name = @entity_configuration.try(:organ_name).to_s
    title = 'Registros de conteúdos por áreas de conhecimento'

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
        rowspan: 1,
        position: :center,
        vposition: :center
      )
    rescue
      entity_logo_cell = make_cell(content: '', width: 70, rowspan: 1)
    end

    entity_organ_and_unity_cell = make_cell(
      content: "#{entity_name}\n#{organ_name}\n" + "#{@knowledge_area_content_records.first.content_record.unity.name}",
      size: 12,
      leading: 1.5,
      align: :center,
      valign: :center,
      rowspan: 1,
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
    @identification_header_cell = make_cell(
      content: '',
      size: 12,
      font_style: :bold,
      background_color: 'FEFEFE',
      height: 0,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 5
    )

    @general_information_header_cell = make_cell(
      content: 'Registros gerais',
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 5
    )
    @unity_header = make_cell(content: 'Unidade', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    @classroom_header = make_cell(content: 'Turma', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    @teacher_header = make_cell(content: 'Professor', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    @period_header = make_cell(content: 'Período', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    if @show_daily_activities_in_knowledge_area_content_record_report
      @daily_acitivies_header = make_cell(content: 'Registro das atividades', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    end

    @unity_cell = make_cell(content:  @knowledge_area_content_records.first.content_record.unity.name, borders: [:bottom, :left, :right], size: 10, width: 240, align: :left, padding: [0, 2, 4, 4])
    @classroom_cell = make_cell(content: @knowledge_area_content_records.first.content_record.classroom.description, borders: [:bottom, :left, :right], size: 10, align: :left, padding: [0, 2, 4, 4])
    @teacher_cell = make_cell(content: @current_teacher.name, borders: [:bottom, :left, :right], size: 10, align: :left, padding: [0, 2, 4, 4])
    @period_cell = make_cell(content: (@date_start == '' || @date_end == '' ? '-' : "#{@date_start} a #{@date_end}"), borders: [:bottom, :left, :right], size: 10, align: :left, padding: [0, 2, 4, 4])

    @record_date_header = make_cell(content: 'Data', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    @knowledge_area_header = make_cell(content: "Áreas de conhecimento / #{Translator.t('activerecord.attributes.knowledge_area_content_record.contents')}", size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    @habilidade_header = make_cell(content: 'Habilidade', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
  end

  def identification
    title_identification = [
      [@identification_header_cell]
    ]

    identification_table_data = [
      [@unity_header, @classroom_header],
      [@unity_cell, @classroom_cell],
      [@teacher_header, @period_header],
      [@teacher_cell, @period_cell]
    ]

    table(title_identification, width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end

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
    records = @knowledge_area_content_records.to_a
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
    start_new_content_page if cursor < 80

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

    start_new_content_page if cursor < 60

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
    @show_daily_activities_in_knowledge_area_content_record_report ? 4 : 3
  end

  def render_records_table(records)
    headers = [
      make_cell(content: 'Data', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4]),
      make_cell(
        content: "Áreas de conhecimento / #{Translator.t('activerecord.attributes.knowledge_area_content_record.contents')}",
        size: 8,
        font_style: :bold,
        borders: [:left, :right, :top],
        background_color: 'FFFFFF',
        padding: [2, 2, 4, 4]
      ),
      make_cell(content: 'Habilidade', size: 8, font_style: :bold, borders: [:left, :right, :top], background_color: 'FFFFFF', padding: [2, 2, 4, 4])
    ]

    if @show_daily_activities_in_knowledge_area_content_record_report
      headers << make_cell(
        content: 'Registro das atividades',
        size: 8,
        font_style: :bold,
        borders: [:left, :right, :top],
        background_color: 'FFFFFF',
        padding: [2, 2, 4, 4]
      )
    end

    table_data = [headers] + records.map { |record| content_record_row(record) }
    render_chunked_table(table_data, column_widths: content_record_column_widths)
  end

  def content_record_column_widths
    date_width = [30 * 0.75, width_of('99/99/9', size: 8) + 8].max
    remaining_width = bounds.width - date_width
    other_columns = @show_daily_activities_in_knowledge_area_content_record_report ? 3 : 2
    other_width = remaining_width / other_columns

    widths = { 0 => date_width, 1 => other_width, 2 => other_width }
    widths[3] = other_width if @show_daily_activities_in_knowledge_area_content_record_report
    widths
  end

  def content_record_row(knowledge_area_content_record)
    content_record = knowledge_area_content_record.content_record
    knowledge_area_descriptions = knowledge_area_content_record.knowledge_areas.map(&:description).join(', ')

    knowledge_area_and_content = [
      knowledge_area_descriptions.to_s.gsub("\n", ' ').squeeze(' '),
      content_cell_content(content_record).to_s.gsub("\n", ' ').squeeze(' ')
    ].join("\n")

    texto_praticas_pedagogicas_e_habilidades = [
      content_record.daily_activities_record.to_s.gsub("\n", ' ').squeeze(' '),
      objective_cell_content(content_record)
    ].join("\n")

    colspan_value = @show_daily_activities_in_knowledge_area_content_record_report ? 2 : 1

    [
      make_cell(content: content_record.record_date.strftime('%d/%m'), size: 8, align: :left),
      make_cell(content: knowledge_area_and_content, size: 8, align: :left),
      make_cell(content: texto_praticas_pedagogicas_e_habilidades, size: 7, align: :left, colspan: colspan_value)
    ]
  end

  def body
    position_below_header
    identification
    general_information
    signatures
  end

  def content_cell_content(content_record)
    content_record.contents_ordered.map(&:to_s).join(', ')
  end

  def objective_cell_content(content_record)
    content_record.objectives_ordered.map(&:to_s).join("\n")
  end

  def signatures
    start_new_content_page if cursor < 55

    move_down 30
    text_box("______________________________________________\nProfessor(a)", size: 10, align: :center, at: [0, cursor], width: 260)
    text_box("______________________________________________\nCoordenador(a)/diretor(a)", size: 10, align: :center, at: [306, cursor], width: 260)
  end
end
