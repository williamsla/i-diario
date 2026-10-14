require 'action_view'
require 'prawn/measurement_extensions'

class BaseReport
  include Prawn::View
  include I18n::Alchemy::NumericParser
  include ActionView::Helpers::NumberHelper

  GAP = 8.freeze

  def initialize(page_layout = :portrait)
    current_configuration = GeneralConfiguration.current
    @display_header_on_all_reports_pages = current_configuration.display_header_on_all_reports_pages
    @display_daily_activies_log = current_configuration.display_daily_activies_log
    @show_daily_activities_in_knowledge_area_content_record_report =
      current_configuration.show_daily_activities_in_knowledge_area_content_record_report

    @document = Prawn::Document.new(
      page_size: 'A4',
      page_layout: page_layout,
      left_margin: 5.mm,
      right_margin: 5.mm,
      top_margin: 5.mm,
      bottom_margin: 5.mm
    )
  end

  protected

  def page_header
    repeat(lambda { |pg| (@display_header_on_all_reports_pages ? true : pg == 1) }) do
      yield
    end

    @cursor_page = cursor - GAP

    move_down GAP unless @display_header_on_all_reports_pages
  end

  def page_content
    @cursor_page = cursor unless page_number == 1 || @display_header_on_all_reports_pages
    position_below_header

    if @display_header_on_all_reports_pages
      bounding_box([0, @cursor_page], width: bounds.width, height: @cursor_page - 10) do
        yield
      end
    else
      yield
    end
  end

  def position_below_header
    return unless @display_header_on_all_reports_pages && @cursor_page
    return unless cursor > @cursor_page

    move_cursor_to(@cursor_page)
  end

  def start_new_content_page
    start_new_page
    position_below_header
  end

  def page_footer(draw_datetime: false)
    yield if block_given?

    repeat(:all) { draw_text("Data e hora: #{Time.zone.now.strftime("%d/%m/%Y %H:%M")}", size: 8, at: [0, 0]) } if draw_datetime

    string = "Página <page> de <total>"

    options = {
      at: [bounds.right - 150, 6],
      width: 150,
      size: 8,
      align: :right
    }

    number_pages(string, options)
  end

  def footer
    page_footer(draw_datetime: true)
  end

  def inline_formated_cell_header(text)
    "<font size='8'><b>#{text}</b></font>\n"
  end

  def render_chunked_table(table_data, **options)
    source_rows = table_data.map { |row| Array(row).map { |cell| cell_draw_spec(cell) } }
    headers = source_rows.first
    rows = source_rows.drop(1)
    return if headers.blank?

    table_options = {
      row_colors: ['DEDEDE', 'FFFFFF'],
      width: bounds.width,
      header: true
    }.merge(options)

    apply_borders = lambda do |t|
      t.cells.border_width = 0.25
      t.row(0).border_top_width = 0.25
      t.row(-1).border_bottom_width = 0.25
      t.column(0).border_left_width = 0.25
      t.column(-1).border_right_width = 0.25
    end

    header_height, row_heights = estimate_table_row_heights(headers, rows, table_options, apply_borders)

    index = 0
    while index < rows.size
      needed = header_height + row_heights[index] + 20
      if cursor < needed && @cursor_page && cursor < (@cursor_page - 30)
        start_new_content_page
      end

      available = [cursor - 20, header_height + 1].max
      used = header_height
      count = 0

      while index + count < rows.size
        next_height = row_heights[index + count]
        break if count.positive? && (used + next_height) > available

        used += next_height
        count += 1
      end
      count = 1 if count.zero?

      table = fit_report_table(materialize_rows([headers] + rows[index, count]), table_options, &apply_borders)
      if table.height > (cursor - 12) && @cursor_page && cursor < (@cursor_page - 30)
        start_new_content_page
      end
      table.draw
      index += count
    end
  end

  def estimate_table_row_heights(headers, rows, table_options, apply_borders)
    header_height = fit_report_table(materialize_rows([headers]), table_options, &apply_borders).height
    row_heights = rows.map do |row|
      measured = fit_report_table(materialize_rows([headers, row]), table_options, &apply_borders).height - header_height
      [measured, 16].max
    end

    [header_height, row_heights]
  rescue Prawn::Errors::CannotFit
    column_count = [headers.length, 1].max
    column_width = bounds.width / column_count
    header_height = 16.0
    row_heights = rows.map do |row|
      max_height = row.map { |cell| height_of(cell_content_for_height(cell), width: column_width, size: 8) }.max
      [max_height + 8, 16].max
    end

    [header_height, row_heights]
  end

  def materialize_rows(rows)
    rows.map { |row| row.map { |spec| materialize_cell(spec) } }
  end

  def materialize_cell(spec)
    options = spec.dup
    options[:borders] = spec[:borders].dup if spec[:borders]
    options[:padding] = spec[:padding].dup if spec[:padding]
    make_cell(options)
  end

  def cell_draw_spec(cell)
    return { content: cell.to_s } unless defined?(Prawn::Table::Cell) && cell.is_a?(Prawn::Table::Cell)

    assigned_width = cell.instance_variable_get(:@width)
    assigned_height = cell.instance_variable_get(:@height)

    spec = { content: cell.content.to_s }
    spec[:size] = cell.size if cell.respond_to?(:size) && cell.size
    spec[:font_style] = cell.font_style if cell.respond_to?(:font_style) && cell.font_style
    spec[:align] = cell.align if cell.respond_to?(:align) && cell.align
    spec[:valign] = cell.valign if cell.respond_to?(:valign) && cell.valign
    spec[:borders] = Array(cell.borders).dup if cell.respond_to?(:borders) && cell.borders
    spec[:padding] = Array(cell.padding).dup if cell.respond_to?(:padding) && cell.padding
    spec[:background_color] = cell.background_color if cell.respond_to?(:background_color) && cell.background_color
    spec[:text_color] = cell.text_color if cell.respond_to?(:text_color) && cell.text_color
    spec[:colspan] = cell.colspan if cell.respond_to?(:colspan) && cell.colspan.to_i > 1
    spec[:rowspan] = cell.rowspan if cell.respond_to?(:rowspan) && cell.rowspan.to_i > 1
    spec[:inline_format] = true if cell.respond_to?(:inline_format?) && cell.inline_format?
    spec[:leading] = cell.leading if cell.respond_to?(:leading) && cell.leading
    spec[:width] = assigned_width if assigned_width
    spec[:height] = assigned_height if assigned_height
    spec
  end

  def fit_report_table(data, table_options, &block)
    opts = fitted_table_options(table_options)
    make_table(data, opts, &block)
  rescue Prawn::Errors::CannotFit
    make_table(data, opts.except(:width, :column_widths), &block)
  end

  def fitted_table_options(table_options)
    opts = table_options.dup
    opts[:width] ||= bounds.width
    widths = opts[:column_widths]
    return opts unless widths.is_a?(Hash) && widths.any?

    sum = widths.values.inject(0.0, :+)
    return opts if sum <= 0

    scale = opts[:width] / sum
    opts[:column_widths] = widths.each_with_object({}) { |(key, value), hash| hash[key] = value * scale }
    opts[:width] = opts[:column_widths].values.inject(0.0, :+)
    opts
  end

  def cell_content_for_height(cell)
    if cell.respond_to?(:content)
      cell.content.to_s
    elsif cell.is_a?(Hash)
      cell[:content].to_s
    else
      cell.to_s
    end
  end

  def numeric_parser
    I18n::Alchemy::NumericParser
  end

  def numeric_precision(value, precision: 2)
    number_with_precision(value, precision: precision)
  end

  def numeric_truncate_precision(value, precision: 2)
    value.truncate(precision)
  end

  def entity_logo_io
    return if @entity_configuration.blank?

    @entity_configuration.logo_io_for_report
  end

  def text_box_truncate(title, information)
    start_new_page if cursor < 45

    draw_text(title, size: 8, style: :bold, at: [5, cursor - 10])

    begin
      if information.class.eql?(Array)
        text_formatted = []

        information.each do |text|
          if text[:styles].include?(:bold)
            text[:text] = "<b>#{text[:text]}</b>"
          end
          if text[:styles].include?(:italic)
            text[:text] = "<i>#{text[:text]}</i>"
          end
          if text[:styles].include?(:underline)
            text[:text]= "<u>#{text[:text]}</u>"
          end

          text_formatted << text[:text]
        end

        information = text_formatted.join(" ")
      end

      text_height = height_of(information, width: bounds.width - 10, size: 10) + 180
      box_height = (text_height > cursor ? cursor : text_height)

      bounding_box([0, cursor], width: bounds.width, height: box_height - 5) do
        line_width 0.5
        stroke_bounds
        information = text_box(
          information.gsub("</p>", "</p><br>"),
          width: bounds.width - 10,
          overflow: :truncate,
          size: 10,
          at: [5, box_height - 20],
          inline_format: true
        )
      end

      start_new_page if information.present?
    end while information.present?
  end

  def process_html_text(html_content)
    return nil if html_content.blank?

    processed_text = html_content.to_s
    processed_text = processed_text.gsub(/<br\s*\/?>/i, "\n")
                                   .gsub(/<\/p>\s*<p[^>]*>/i, "\n\n")
                                   .gsub(/<\/div>\s*<div[^>]*>/i, "\n\n")
                                   .gsub(/<\/li>\s*<li[^>]*>/i, "\n")
                                   .gsub(/<p[^>]*>/i, "")
                                   .gsub(/<\/p>/i, "\n")
                                   .gsub(/<div[^>]*>/i, "")
                                   .gsub(/<\/div>/i, "\n")
                                   .gsub(/<li[^>]*>/i, "")
                                   .gsub(/<\/li>/i, "\n")
                                   .gsub(/<[^>]*>/, "")
    processed_text = CGI.unescapeHTML(processed_text).tr("\u00A0", " ")
    processed_text = processed_text.gsub(/^[ \t]+$/, "")
                                   .gsub(/[ \t]+\n/, "\n")
                                   .gsub(/\n{3,}/, "\n\n")
                                   .strip
    processed_text.presence
  rescue StandardError
    CGI.unescapeHTML(html_content.to_s.gsub(/<[^>]*>/, "")).strip.presence
  end

  def text_box_dynamic_height(title, information)
    return if information.blank?

    text_to_render = information.to_s
    if text_to_render.match?(/<[^>]+>/)
      text_to_render = process_html_text(text_to_render) || text_to_render
    end
    text_to_render = text_to_render.to_s.strip
    return if text_to_render.blank?

    title_height = 12
    title_spacing = 5
    padding = 8
    horizontal_inset = 5
    footer_reserve = 20
    text_width = bounds.width - (horizontal_inset * 2)
    remaining_text = text_to_render
    iteration_count = 0
    stalls = 0

    while remaining_text.present?
      iteration_count += 1
      break if iteration_count > 50

      minimum_box = title_height + title_spacing + padding + 14
      start_new_content_page if cursor < minimum_box + footer_reserve

      available_height = cursor - footer_reserve
      break if available_height < minimum_box

      max_text_height = available_height - title_height - title_spacing - padding
      natural_height = begin
        height_of(remaining_text, width: text_width, size: 10)
      rescue StandardError
        14
      end

      line_slack = 12
      text_fits = natural_height <= max_text_height
      text_height = if text_fits
                      [natural_height + line_slack, max_text_height].min
                    else
                      max_text_height
                    end
      text_height = [text_height, 12].max
      box_height = [title_height + title_spacing + text_height + padding, available_height].min
      text_before = remaining_text

      bounding_box([0, cursor], width: bounds.width, height: box_height) do
        line_width 0.5
        stroke_bounds
        draw_text(title, size: 8, style: :bold, at: [horizontal_inset, box_height - 8])

        leftover = text_box(
          remaining_text,
          width: text_width,
          height: [box_height - title_height - title_spacing - 4, 12].max,
          at: [horizontal_inset, box_height - title_height - title_spacing],
          overflow: :truncate,
          size: 10
        )
        remaining_text = normalize_text_box_remainder(leftover)
      end

      if remaining_text.blank?
        break
      elsif remaining_text.length >= text_before.length
        stalls += 1
        break if stalls > 1

        start_new_content_page
      elsif text_fits
        stalls = 0
      else
        stalls = 0
        start_new_content_page
      end
    end

    move_down 5
  rescue StandardError => e
    Rails.logger.error "Erro em text_box_dynamic_height para #{title}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    move_down 5
  end

  def normalize_text_box_remainder(value)
    text = if value.is_a?(Array)
             value.map { |item| item.is_a?(Hash) ? (item[:text] || item["text"]).to_s : item.to_s }.join
           else
             value.to_s
           end
    stripped = text.strip
    stripped.empty? ? "" : stripped
  end

  def text_box_overflow_to_new_page(information, size, at, width, height)
    begin
      if information.class.eql?(Array)
        text_formatted = []

        text_formatted << information.map { |text| text[:text] }

        information = text_formatted.join(" ")
      end

      information = text_box(
        information,
        size: size,
        at: at,
        width: width,
        height: height,
        overflow: :truncate,
        inline_format: true
      )

      if information.present?
        start_new_page
        at = nil
        height = bounds.height
      end
    end while information.present?
  end
end
