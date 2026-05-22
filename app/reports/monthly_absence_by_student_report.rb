class MonthlyAbsenceByStudentReport < BaseReport
  def self.build(entity_configuration, form)
    new(:portrait).build(entity_configuration, form)
  end

  def build(entity_configuration, form)
    @entity_configuration = entity_configuration
    @form = form
    @rows = form.rows
    @months = form.parsed_months

    header
    body
    footer

    self
  end

  private

  def header
    title_cell = make_cell(
      content: 'Faltas por mês',
      size: 12,
      font_style: :bold,
      background_color: 'DEDEDE',
      height: 20,
      padding: [2, 2, 4, 4],
      align: :center,
      colspan: 2
    )

    begin
      logo_cell = make_cell(
        image: open(@entity_configuration.logo.url),
        fit: [50, 50],
        width: 70,
        rowspan: 4,
        position: :center,
        vposition: :center
      )
    rescue StandardError
      logo_cell = make_cell(content: '', width: 70, rowspan: 4)
    end

    entity_name = @entity_configuration&.entity_name || ''
    organ_name = @entity_configuration&.organ_name || ''
    unity_name = @form.unity&.name || ''

    entity_organ_and_unity_cell = make_cell(
      content: "#{entity_name}\n#{organ_name}\n#{unity_name}",
      size: 12,
      leading: 1.5,
      align: :center,
      valign: :center,
      rowspan: 4,
      padding: [6, 0, 8, 0]
    )

    page_header do
      table([[title_cell], [logo_cell, entity_organ_and_unity_cell]], width: bounds.width) do
        cells.border_width = 0.25
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end
    end

    move_down GAP
    text "Ano letivo: #{@form.parsed_year}", size: 10, style: :bold
    move_down GAP
  end

  def body
    page_content do
      table_data = [table_headers]

      @rows.each do |row|
        table_data << table_row(row)
      end

      table(table_data, width: bounds.width, header: true, row_colors: ['DEDEDE', 'FFFFFF']) do
        cells.border_width = 0.25
        cells.size = 8
        row(0).font_style = :bold
        row(0).align = :center
        cells.valign = :center
        row(0).border_top_width = 0.25
        row(-1).border_bottom_width = 0.25
        column(0).border_left_width = 0.25
        column(-1).border_right_width = 0.25
      end
    end
  end

  def table_headers
    headers = [
      make_cell(content: 'TURMA', font_style: :bold, align: :center),
      make_cell(content: 'ALUNO', font_style: :bold, align: :center)
    ]

    @months.each do |month|
      headers << make_cell(
        content: "#{@form.month_label(month)}\n FALTAS",
        font_style: :bold,
        align: :center
      )
    end

    headers << make_cell(
      content: "TOTAL \n FALTAS",
      font_style: :bold,
      align: :center
    )

    headers
  end

  def table_row(row)
    cells = [
      make_cell(content: row.classroom_description),
      make_cell(content: row.student_name)
    ]

    total = 0

    @months.each do |month|
      count = row.absences_by_month[month] || 0
      total += count
      cells << make_cell(content: count.to_s, align: :center)
    end

    cells << make_cell(content: total.to_s, align: :center, font_style: :bold)

    cells
  end
end
