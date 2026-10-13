# frozen_string_literal: true

class AeePaeePdf < BaseReport
  def self.build(entity_configuration, teaching_plan)
    new.build(entity_configuration, teaching_plan)
  end

  def build(entity_configuration, teaching_plan)
    @entity_configuration = entity_configuration
    @teaching_plan = teaching_plan
    @detail = teaching_plan.aee_teaching_plan_detail || teaching_plan.build_aee_teaching_plan_detail

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
      content: I18n.t('teaching_plans.aee_paee.pdf.title'),
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
    unity_name = @teaching_plan.unity.to_s

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
      organization
      legal_text
      objectives
      text_box_truncate(I18n.t('teaching_plans.aee_paee.pdf.activities'), present_text(@detail.activities))
      text_box_truncate(I18n.t('teaching_plans.aee_paee.pdf.strategies'), present_text(@teaching_plan.methodology))
      text_box_truncate(I18n.t('teaching_plans.aee_paee.pdf.resources'), present_text(@detail.resources))
      text_box_truncate(I18n.t('teaching_plans.aee_paee.pdf.evaluation'), present_text(@teaching_plan.evaluation))
      signatures
      document_place_and_date
    end
  end

  def identification
    rows = [
      identification_row(I18n.t('teaching_plans.aee_paee.pdf.student'), @teaching_plan.student.to_s),
      identification_row(I18n.t('teaching_plans.aee_paee.pdf.grade'), @teaching_plan.grade.to_s),
      identification_row(I18n.t('teaching_plans.aee_paee.pdf.age'), student_age),
      identification_row(I18n.t('teaching_plans.aee_paee.pdf.school'), @teaching_plan.unity.to_s),
      identification_row(
        AeeTeachingPlanDetail.human_attribute_name(:specialized_teacher_name),
        @detail.specialized_teacher_name
      ),
      identification_row(
        AeeTeachingPlanDetail.human_attribute_name(:regular_teacher_name),
        @detail.regular_teacher_name
      )
    ]

    table(rows, width: bounds.width, cell_style: { size: 10, padding: [4, 4, 4, 4] }) do
      cells.border_width = 0.25
      column(0).font_style = :bold
      column(0).width = 160
    end

    move_down GAP * 2
  end

  def organization
    text I18n.t('teaching_plans.aee_paee.organization_legend'), size: 10, style: :bold
    move_down GAP

    composition = @detail.attendance_composition_humanize.presence || '-'

    rows = [
      identification_row(
        I18n.t('aee.fields.school_term_type'),
        @teaching_plan.school_term_type.to_s
      ),
      identification_row(
        AeeTeachingPlanDetail.human_attribute_name(:attendance_frequency),
        @detail.attendance_frequency
      ),
      identification_row(
        AeeTeachingPlanDetail.human_attribute_name(:attendance_duration),
        @detail.attendance_duration
      ),
      identification_row(
        AeeTeachingPlanDetail.human_attribute_name(:attendance_composition),
        composition
      )
    ]

    table(rows, width: bounds.width, cell_style: { size: 10, padding: [4, 4, 4, 4] }) do
      cells.border_width = 0.25
      column(0).font_style = :bold
      column(0).width = 160
    end

    move_down GAP * 2
  end

  def legal_text
    start_new_page if cursor < 80
    text I18n.t('teaching_plans.aee_paee.legal_text'), size: 9, align: :justify, leading: 2
    move_down GAP * 2
  end

  def objectives
    text I18n.t('teaching_plans.aee_paee.objectives_legend'), size: 10, style: :bold
    move_down GAP

    text_box_truncate(
      AeeTeachingPlanDetail.human_attribute_name(:student_characteristics),
      present_text(@detail.student_characteristics)
    )
    text_box_truncate(
      AeeTeachingPlanDetail.human_attribute_name(:general_objectives),
      present_text(@detail.general_objectives)
    )
    text_box_truncate(
      AeeTeachingPlanDetail.human_attribute_name(:cognitive_objectives),
      present_text(@detail.cognitive_objectives)
    )
    text_box_truncate(
      AeeTeachingPlanDetail.human_attribute_name(:psychomotor_objectives),
      present_text(@detail.psychomotor_objectives)
    )
    text_box_truncate(
      AeeTeachingPlanDetail.human_attribute_name(:socioemotional_objectives),
      present_text(@detail.socioemotional_objectives)
    )
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
      [AeeTeachingPlanDetail.human_attribute_name(:regular_teacher_name), @detail.regular_teacher_name],
      [AeeTeachingPlanDetail.human_attribute_name(:specialized_teacher_name), @detail.specialized_teacher_name],
      [AeeTeachingPlanDetail.human_attribute_name(:mediator_name), @detail.mediator_name],
      [AeeTeachingPlanDetail.human_attribute_name(:pedagogical_coordinator_name), @detail.pedagogical_coordinator_name],
      [AeeTeachingPlanDetail.human_attribute_name(:school_management_name), @detail.school_management_name],
      [AeeTeachingPlanDetail.human_attribute_name(:responsible_name), @detail.responsible_name]
    ]
  end

  def document_place_and_date
    move_down GAP * 2
    text @detail.location_and_date, size: 10, align: :right
  end

  def identification_row(label, value)
    [
      make_cell(content: label.to_s),
      make_cell(content: value.to_s.presence || '-')
    ]
  end

  def student_age
    AeeCaseStudy.age_label_for(@teaching_plan.student&.birth_date).presence || '-'
  end

  def present_text(value)
    ActionController::Base.helpers.strip_tags(value.to_s).to_s.gsub('&nbsp;', ' ').strip.presence || '-'
  end
end
