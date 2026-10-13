# frozen_string_literal: true

class AeeCaseStudyPdf < BaseReport
  def self.build(entity_configuration, aee_case_study)
    new.build(entity_configuration, aee_case_study)
  end

  def build(entity_configuration, aee_case_study)
    @entity_configuration = entity_configuration
    @aee_case_study = aee_case_study

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
      content: I18n.t('aee_case_studies.pdf.title'),
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
    unity_name = @aee_case_study.unity.to_s

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
      stages
      legal_text
      signatures
      document_place_and_date
    end
  end

  def identification
    rows = [
      identification_row(:student, @aee_case_study.student.to_s),
      identification_row(:grade_stage, @aee_case_study.grade_stage),
      identification_row(:age, @aee_case_study.age),
      identification_row(:identification, @aee_case_study.identification),
      identification_row(:modality, @aee_case_study.modality)
    ]

    table(rows, width: bounds.width, cell_style: { size: 10, padding: [4, 4, 4, 4] }) do
      cells.border_width = 0.25
      column(0).font_style = :bold
      column(0).width = 130
    end

    move_down GAP * 2
  end

  def identification_row(attribute, value)
    [
      make_cell(content: AeeCaseStudy.human_attribute_name(attribute)),
      make_cell(content: value.to_s)
    ]
  end

  def stages
    text I18n.t('aee_case_studies.pdf.stages_intro'), size: 10, style: :bold
    move_down GAP

    text_box_truncate(I18n.t('aee_case_studies.pdf.stage_i'), @aee_case_study.individual_demands.presence || '-')
    text_box_truncate(I18n.t('aee_case_studies.pdf.stage_ii'), @aee_case_study.barriers_and_context.presence || '-')
    text_box_truncate(I18n.t('aee_case_studies.pdf.stage_iii'), @aee_case_study.potentialities_and_support.presence || '-')
    text_box_truncate(I18n.t('aee_case_studies.pdf.stage_iv'), @aee_case_study.accessibility_strategies.presence || '-')
    text_box_truncate(
      AeeCaseStudy.human_attribute_name(:final_considerations),
      @aee_case_study.final_considerations.presence || '-'
    )
  end

  def legal_text
    start_new_page if cursor < 80
    move_down GAP
    text I18n.t('aee_case_studies.form.legal_text'), size: 9, align: :justify, leading: 2
    move_down GAP * 2
  end

  def signatures
    signature_lines.each do |label, value|
      start_new_page if cursor < 24
      text "#{label}: #{value.presence || '_______________________________________'} ", size: 10
      move_down 8
    end
  end

  def signature_lines
    [
      [AeeCaseStudy.human_attribute_name(:regular_teacher_name), @aee_case_study.regular_teacher_name],
      [AeeCaseStudy.human_attribute_name(:specialized_teacher_name), @aee_case_study.specialized_teacher_name],
      [AeeCaseStudy.human_attribute_name(:mediator_name), @aee_case_study.mediator_name],
      [AeeCaseStudy.human_attribute_name(:pedagogical_coordinator_name), @aee_case_study.pedagogical_coordinator_name],
      [AeeCaseStudy.human_attribute_name(:school_management_name), @aee_case_study.school_management_name],
      [AeeCaseStudy.human_attribute_name(:responsible_name), @aee_case_study.responsible_name]
    ]
  end

  def document_place_and_date
    move_down GAP * 2
    text @aee_case_study.location_and_date, size: 10, align: :right
  end
end
