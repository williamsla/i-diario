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
    general_information_headers = [
      @date_header,
      @class_number_header,      
      @conteudo_header
      
    ]

    if @display_daily_activies_log
      general_information_headers << @daily_acitivies_header
    end
    general_information_headers << @habilidade_header

    general_information_cells = []

    @discipline_content_record.each do |discipline_content_record|
      date_cell = make_cell(content: discipline_content_record.content_record.record_date.strftime("%d/%m"), size: 8, align: :left, width:30)
      begin
        class_number = make_cell(content: "#{discipline_content_record.class_number}", size: 8, align: :center)
      rescue
        class_number = make_cell(content: "-", size: 8, align: :center)
      end
      
      texto_praticas_pedagogicas_e_habilidades = [ 
        discipline_content_record.content_record.daily_activities_record.to_s.gsub("\n", ' ').squeeze(' ') ,
        objective_cell_content(discipline_content_record.content_record)        
      ].join("\n")

      content_cell = make_cell(content: content_cell_content(discipline_content_record.content_record), size: 8, align: :left, colspan: 1, width: 150)
      habilidade_cell = make_cell(content: texto_praticas_pedagogicas_e_habilidades, size: 7, align: :left, colspan: 3)
      
      general_information_cells << [
        date_cell,
        class_number,
        content_cell,
        habilidade_cell
      ]

      # if @display_daily_activies_log
      #   daily_acitivies_cell = make_cell(content: discipline_content_record.content_record.daily_activities_record.to_s, size: 8, align: :left)
      #   general_information_cells.last << daily_acitivies_cell
      # end
      
    end

    general_information_table_data = [general_information_headers]
    general_information_table_data.concat(general_information_cells)

    table(general_information_table_data, row_colors: ['DEDEDE', 'FFFFFF'], width: bounds.width, header: true) do
      cells.border_width = 0.25
      row(0).border_top_width = 0.25
      row(-1).border_bottom_width = 0.25
      column(0).border_left_width = 0.25
      column(-1).border_right_width = 0.25
    end
  end

  def body
    page_content do
      identification
      general_information
      signatures
    end
  end

  def content_cell_content(content_record)
    content_record.contents_ordered.map(&:to_s).join(", ")
  end

  def objective_cell_content(content_record)
    begin
      content_record.objectives_ordered.map(&:to_s).join("\n")
    rescue
      ""
    end
  end

  def signatures
    start_new_page if cursor < 55
    
    move_down 5
    begin
      # Carrega todos os registros em memória e soma o class_number
      total_aulas = @discipline_content_record.to_a.sum { |record| record.class_number.to_i }
      text_box("Total de aulas dadas: #{total_aulas}", size: 12, align: :left, at: [0, cursor], width: 260)
    rescue => e
      # Fallback para contagem simples em caso de erro
      total_aulas = @discipline_content_record.count
      text_box("Total de aulas dadas: #{total_aulas}", size: 12, align: :left, at: [0, cursor], width: 260)
    end
    
    move_down 30
    text_box("______________________________________________\nProfessor(a)", size: 10, align: :center, at: [0, cursor], width: 260)
    text_box("______________________________________________\nCoordenador(a)", size: 10, align: :center, at: [306, cursor], width: 260)
  end
end
