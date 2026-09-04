module ConceptualExamHelper
  def conceptual_exam_label(status)
    return '' if status.blank?

    case status.to_s
    when ConceptualExamStatus::INCOMPLETE, 'incomplete'
      'label label-warning'
    when ConceptualExamStatus::COMPLETE, 'complete'
      'label label-success'
    when ConceptualExamStepOverviewFetcher::PENDING, 'pending'
      'label label-info'
    end
  end

  def conceptual_exam_status_label(status)
    case status.to_s
    when ConceptualExamStepOverviewFetcher::PENDING, 'pending'
      I18n.t('conceptual_exams.index.stat_pending')
    else
      ConceptualExamStatus.t(status)
    end
  end

  def conceptual_exam_row_action_title(status)
    case status.to_s
    when ConceptualExamStatus::INCOMPLETE, 'incomplete'
      I18n.t('conceptual_exams.students_by_step.continue')
    else
      I18n.t('conceptual_exams.form.edit')
    end
  end

  def conceptual_exam_progress_bar(overview)
    return if overview.blank? || overview.total.to_i.zero?

    complete_pct = ((overview.complete.to_f / overview.total) * 100).round(1)
    incomplete_pct = ((overview.incomplete.to_f / overview.total) * 100).round(1)
    pending_pct = [100 - complete_pct - incomplete_pct, 0].max

    content_tag(:div, class: 'progress conceptual-exams-progress') do
      safe_join(
        [
          progress_segment('progress-bar-success', complete_pct, overview.complete),
          progress_segment('progress-bar-warning', incomplete_pct, overview.incomplete),
          progress_segment('progress-bar-info', pending_pct, overview.pending)
        ]
      )
    end
  end

  def any_student_exempted_from_discipline?
    @conceptual_exam.conceptual_exam_values.any? { |value| value.exempted_discipline.to_s == 'true' }
  end

  def skip_conceptual_exam_value_field?(value)
    value.marked_for_destruction? || value.marked_as_invisible?
  end

  def ordered_conceptual_exam_values
    @conceptual_exam.conceptual_exam_values
                    .sort_by { |conceptual_exam_value|
                      [
                        conceptual_exam_value.discipline.sequence.to_i,
                        conceptual_exam_value.discipline.description
                      ]
                    }
                    .group_by { |conceptual_exam_value|
                      conceptual_exam_value.discipline.knowledge_area
                    }
                    .sort_by { |knowledge_area, _conceptual_exam_values|
                      [
                        knowledge_area.sequence.to_i,
                        knowledge_area.description
                      ]
                    }
  end

  private

  def progress_segment(css_class, percentage, count)
    return ''.html_safe if percentage <= 0 || count.to_i <= 0

    content_tag(
      :div,
      '',
      class: "progress-bar #{css_class}",
      style: "width: #{percentage}%",
      title: count.to_s
    )
  end
end
