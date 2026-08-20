# frozen_string_literal: true

class AeeIndividualPlanPdf < BaseReport
  def self.build(entity_configuration, aee_individual_plan)
    new.build(entity_configuration, aee_individual_plan)
  end

  def build(entity_configuration, aee_individual_plan)
    @entity_configuration = entity_configuration
    @aee_individual_plan = aee_individual_plan

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
      content: I18n.t('aee_individual_plans.pdf.title'),
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
    unity_name = @aee_individual_plan.unity.to_s

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
      legal_text
      text_box_truncate(
        AeeIndividualPlan.human_attribute_name(:characteristics),
        present_text(@aee_individual_plan.characteristics)
      )
      text I18n.t('aee_individual_plans.form.objective_text'), size: 9, align: :justify, leading: 2
      move_down GAP * 2
      skills
      text_box_truncate(
        I18n.t('aee_individual_plans.pdf.difficulties'),
        present_text(@aee_individual_plan.identified_difficulties)
      )
      text_box_truncate(
        I18n.t('aee_individual_plans.pdf.goals'),
        present_text(@aee_individual_plan.goals)
      )
      text_box_truncate(
        AeeIndividualPlan.human_attribute_name(:resources),
        present_text(@aee_individual_plan.resources)
      )
      text_box_truncate(
        AeeIndividualPlan.human_attribute_name(:strategies),
        present_text(@aee_individual_plan.strategies)
      )
      text_box_truncate(
        I18n.t('aee_individual_plans.pdf.monitoring'),
        present_text(@aee_individual_plan.monitoring)
      )
      attendance_records
      text_box_truncate(
        AeeIndividualPlan.human_attribute_name(:short_term_goals),
        present_text(@aee_individual_plan.short_term_goals)
      )
      text_box_truncate(
        AeeIndividualPlan.human_attribute_name(:long_term_goals),
        present_text(@aee_individual_plan.long_term_goals)
      )
      text_box_truncate(
        AeeIndividualPlan.human_attribute_name(:final_considerations),
        present_text(@aee_individual_plan.final_considerations)
      )
      text I18n.t('aee_individual_plans.form.final_considerations_text'), size: 9, align: :justify, leading: 2
      move_down GAP * 2
      signatures
      document_place_and_date
    end
  end

  def identification
    rows = [
      identification_row(:student, @aee_individual_plan.student.to_s),
      identification_row(:birth_date, @aee_individual_plan.birth_date_label),
      identification_row(:age, @aee_individual_plan.age),
      identification_row(:start_on, formatted_date(@aee_individual_plan.start_on)),
      identification_row(:review_on, formatted_date(@aee_individual_plan.review_on)),
      identification_row(:specialized_teacher_name, @aee_individual_plan.specialized_teacher_name),
      identification_row(:unity, @aee_individual_plan.unity.to_s)
    ]

    table(rows, width: bounds.width, cell_style: { size: 10, padding: [4, 4, 4, 4] }) do
      cells.border_width = 0.25
      column(0).font_style = :bold
      column(0).width = 160
    end

    move_down GAP * 2
  end

  def legal_text
    text I18n.t('aee_individual_plans.form.legal_text'), size: 9, align: :justify, leading: 2
    move_down GAP * 2
  end

  def skills
    text I18n.t('aee_individual_plans.pdf.skills'), size: 10, style: :bold
    move_down GAP

    text_box_truncate(
      AeeIndividualPlan.human_attribute_name(:psychomotor_skills),
      present_text(@aee_individual_plan.psychomotor_skills)
    )
    text_box_truncate(
      AeeIndividualPlan.human_attribute_name(:cognitive_skills),
      present_text(@aee_individual_plan.cognitive_skills)
    )
    text_box_truncate(
      AeeIndividualPlan.human_attribute_name(:socioemotional_skills),
      present_text(@aee_individual_plan.socioemotional_skills)
    )
    text_box_truncate(
      AeeIndividualPlan.human_attribute_name(:linguistic_skills),
      present_text(@aee_individual_plan.linguistic_skills)
    )
  end

  def attendance_records
    text I18n.t('aee_individual_plans.pdf.attendance_records'), size: 10, style: :bold
    move_down GAP

    records = @aee_individual_plan.attendance_records
    if records.blank?
      text I18n.t('aee_individual_plans.form.attendance_records_empty'), size: 10
      move_down GAP * 2
      return
    end

    rows = [
      [
        make_cell(content: I18n.t('aee_individual_plans.form.attendance_record_date'), font_style: :bold),
        make_cell(content: I18n.t('aee_individual_plans.form.attendance_record_area'), font_style: :bold),
        make_cell(content: I18n.t('aee_individual_plans.form.attendance_record_text'), font_style: :bold)
      ]
    ]

    records.each do |record|
      rows << [
        make_cell(content: formatted_date(record.record_date)),
        make_cell(content: record.to_s),
        make_cell(content: present_text(record.daily_activities_record))
      ]
    end

    table(rows, width: bounds.width, cell_style: { size: 9, padding: [3, 3, 3, 3] }) do
      cells.border_width = 0.25
      column(0).width = 80
      column(1).width = 120
    end

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
      [AeeIndividualPlan.human_attribute_name(:regular_teacher_name), @aee_individual_plan.regular_teacher_name],
      [AeeIndividualPlan.human_attribute_name(:specialized_teacher_name), @aee_individual_plan.specialized_teacher_name],
      [AeeIndividualPlan.human_attribute_name(:mediator_name), @aee_individual_plan.mediator_name],
      [AeeIndividualPlan.human_attribute_name(:pedagogical_coordinator_name), @aee_individual_plan.pedagogical_coordinator_name],
      [AeeIndividualPlan.human_attribute_name(:school_management_name), @aee_individual_plan.school_management_name],
      [AeeIndividualPlan.human_attribute_name(:responsible_name), @aee_individual_plan.responsible_name]
    ]
  end

  def document_place_and_date
    move_down GAP * 2
    text @aee_individual_plan.location_and_date, size: 10, align: :right
  end

  def identification_row(attribute, value)
    [
      make_cell(content: AeeIndividualPlan.human_attribute_name(attribute)),
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
