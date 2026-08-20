module AeeHelper
  def aee_label(key, fallback = nil)
    return fallback unless is_aee

    I18n.t("aee.fields.#{key}", default: fallback)
  end

  def aee_navigation_label(menu_type, fallback = nil)
    return fallback unless is_aee

    i18n_key = "aee.navigation.#{menu_type}"
    return I18n.t(i18n_key) if I18n.exists?(i18n_key)

    fallback
  end

  def aee_or_translation(aee_key, translation_value)
    return translation_value unless is_aee

    I18n.t("aee.fields.#{aee_key}", default: translation_value)
  end

  def aee_workflow_nav(current_step, student: nil)
    return unless is_aee
    return if params[:modal] == 'true'

    render 'shared/aee_workflow',
           current_step: current_step,
           student: student,
           steps: aee_workflow_steps(student)
  end

  def aee_next_step_button(from, student = nil)
    return unless is_aee

    step = aee_next_step(from, student)
    return if step.blank?

    link_to step[:label], step[:path], class: 'btn btn-success aee-form-next'
  end

  def aee_prefill_notice
    content_tag(:div, class: 'alert alert-success aee-prefill-notice', style: 'display:none') do
      safe_join(
        [
          content_tag(:i, '', class: 'fa-fw fa fa-check'),
          I18n.t('aee.workflow.prefill_notice')
        ],
        ' '
      )
    end
  end

  private

  def aee_workflow_steps(student)
    [
      {
        key: :case_study,
        title: I18n.t('aee.workflow.case_study'),
        hint: I18n.t('aee.workflow.case_study_hint'),
        path: aee_case_study_path_for(student),
        done: aee_case_study_for(student).present?
      },
      {
        key: :paee,
        title: I18n.t('aee.workflow.paee'),
        hint: I18n.t('aee.workflow.paee_hint'),
        path: aee_paee_path_for(student),
        done: aee_paee_for(student).present?
      },
      {
        key: :pei,
        title: I18n.t('aee.workflow.pei'),
        hint: I18n.t('aee.workflow.pei_hint'),
        path: aee_pei_path_for(student),
        done: aee_pei_for(student).present?
      },
      {
        key: :attendance,
        title: I18n.t('aee.workflow.attendance'),
        hint: I18n.t('aee.workflow.attendance_hint'),
        path: aee_attendance_path_for(student),
        done: aee_attendance_for(student)
      }
    ]
  end

  def aee_next_step(from, student)
    mapping = {
      case_study: :paee,
      paee: :pei,
      pei: :attendance
    }
    next_key = mapping[from]
    return if next_key.blank?

    aee_workflow_steps(student).find { |step| step[:key] == next_key }.merge(
      label: I18n.t("aee.workflow.next_#{next_key}")
    )
  end

  def aee_case_study_for(student)
    return if student.blank? || current_user_classroom.blank?

    @aee_case_study_for ||= {}
    @aee_case_study_for[student.id] ||= AeeCaseStudy.find_by(
      student_id: student.id,
      classroom_id: current_user_classroom.id,
      year: current_user_school_year
    )
  end

  def aee_paee_for(student)
    return if student.blank?

    @aee_paee_for ||= {}
    @aee_paee_for[student.id] ||= TeachingPlan
      .includes(:knowledge_area_teaching_plan, :discipline_teaching_plan)
      .where(student_id: student.id, year: current_user_school_year)
      .order(updated_at: :desc)
      .first
  end

  def aee_pei_for(student)
    return if student.blank? || current_user_classroom.blank?

    @aee_pei_for ||= {}
    @aee_pei_for[student.id] ||= AeeIndividualPlan.find_by(
      student_id: student.id,
      classroom_id: current_user_classroom.id,
      year: current_user_school_year
    )
  end

  def aee_case_study_path_for(student)
    record = aee_case_study_for(student)
    return edit_aee_case_study_path(record) if record.present?
    return new_aee_case_study_path(student_id: student.id) if student.present?

    aee_case_studies_path
  end

  def aee_paee_path_for(student)
    plan = aee_paee_for(student)
    if plan&.knowledge_area_teaching_plan
      return edit_knowledge_area_teaching_plan_path(plan.knowledge_area_teaching_plan)
    end
    if plan&.discipline_teaching_plan
      return edit_discipline_teaching_plan_path(plan.discipline_teaching_plan)
    end
    return new_knowledge_area_teaching_plan_path(student_id: student.id) if student.present?

    knowledge_area_teaching_plans_path
  end

  def aee_pei_path_for(student)
    record = aee_pei_for(student)
    return edit_aee_individual_plan_path(record) if record.present?
    return new_aee_individual_plan_path(student_id: student.id) if student.present?

    aee_individual_plans_path
  end

  def aee_attendance_for(student)
    return false if student.blank? || current_user_classroom.blank?

    @aee_attendance_for ||= {}
    @aee_attendance_for[student.id] ||= AeeAttendanceRecord.exists?(
      student_id: student.id,
      classroom_id: current_user_classroom.id,
      year: current_user_school_year
    )
  end

  def aee_attendance_path_for(student)
    return new_aee_attendance_record_path(student_id: student.id) if student.present?

    aee_attendance_records_path
  end
end
