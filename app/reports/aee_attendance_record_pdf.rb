# frozen_string_literal: true

class AeeAttendanceRecordPdf < BaseReport
  def self.build(entity_configuration, aee_attendance_record)
    new.build(entity_configuration, aee_attendance_record)
  end

  def build(entity_configuration, aee_attendance_record)
    @entity_configuration = entity_configuration
    @aee_attendance_record = aee_attendance_record

    if @display_header_on_all_reports_pages
      header
      body
    else
      bounding_box([0, cursor], width: bounds.width, height: bounds.height - GAP) do
        header
        body
      end
    end

    footer
    self
  end

  private

  def header
    header_cell = make_cell(
      content: I18n.t('aee_attendance_records.pdf.title'),
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
        image: open(@entity_configuration.logo.url),
        fit: [50, 50],
        width: 70,
        rowspan: 4,
        position: :center,
        vposition: :center
      )
    rescue
      entity_logo_cell = make_cell(content: '', width: 70, rowspan: 4)
    end

    entity_name = @entity_configuration ? @entity_configuration.entity_name : ''
    organ_name = @entity_configuration ? @entity_configuration.organ_name : ''
    unity_name = @aee_attendance_record.unity.to_s

    entity_organ_and_unity_cell = make_cell(
      content: "#{entity_name}\n#{organ_name}\n#{unity_name}",
      size: 12,
      leading: 1.5,
      align: :center,
      valign: :center,
      rowspan: 4,
      padding: [6, 0, 8, 0]
    )

    table_data = [
      [header_cell],
      [entity_logo_cell, entity_organ_and_unity_cell]
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

  def body
    page_content do
      identification
      session
    end
  end

  def identification
    rows = [
      identification_row(:student, @aee_attendance_record.student.to_s),
      identification_row(:record_date, formatted_date(@aee_attendance_record.record_date)),
      identification_row(:duration, @aee_attendance_record.duration),
      identification_row(:teacher, @aee_attendance_record.teacher.to_s)
    ]

    table(rows, width: bounds.width, cell_style: { size: 10, padding: [4, 4, 4, 4] }) do
      cells.border_width = 0.25
      column(0).font_style = :bold
      column(0).width = 150
    end

    move_down GAP * 2
  end

  def session
    text_box_truncate(
      AeeAttendanceRecord.human_attribute_name(:session_focus),
      present_text(@aee_attendance_record.session_focus)
    )
    text_box_truncate(
      AeeAttendanceRecord.human_attribute_name(:session_objectives),
      present_text(@aee_attendance_record.session_objectives)
    )
    text_box_truncate(
      AeeAttendanceRecord.human_attribute_name(:activities_developed),
      present_text(@aee_attendance_record.activities_developed)
    )
    text_box_truncate(
      AeeAttendanceRecord.human_attribute_name(:student_response),
      present_text(@aee_attendance_record.student_response)
    )
    text_box_truncate(
      AeeAttendanceRecord.human_attribute_name(:next_steps),
      present_text(@aee_attendance_record.next_steps)
    )
  end

  def identification_row(attribute, value)
    [
      make_cell(content: AeeAttendanceRecord.human_attribute_name(attribute)),
      make_cell(content: value.to_s.presence || '-')
    ]
  end

  def formatted_date(value)
    return '-' if value.blank?

    I18n.l(value)
  end

  def present_text(value)
    ActionController::Base.helpers.strip_tags(value.to_s).to_s.gsub('&nbsp;', ' ').strip.presence || '-'
  end
end
