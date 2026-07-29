module PedagogicalTrackingsHelper
  def render_details_link(record, options = {})
    return if record.classroom_id.blank?

    css_class = options.fetch(:class, 'btn btn-link pedagogical-details-link')

    link_to(
      t('pedagogical_trackings.index.see_teachers'),
      '#',
      class: "#{css_class} open_classroom_detail_modal".strip,
      data: {
        classroom_id: record.classroom_id,
        unity_id: record.unity_id,
        start_date: record.start_date.present? ? format(record.start_date) : '',
        end_date: record.end_date.present? ? format(record.end_date) : ''
      }
    )
  end

  def render_school_actions(record)
    unity_id = record.unity_id
    classroom_id = record.classroom_id || 0
    details_link = render_details_link(record)

    desktop_actions = [
      action_button(t('pedagogical_trackings.index.resume_entries'), "openResumeModal(#{unity_id}, #{classroom_id}); return false;"),
      action_button(t('pedagogical_trackings.index.absent_students'), "openFrequencyReportModal(#{unity_id}, #{classroom_id}); return false;"),
      action_button(t('pedagogical_trackings.index.class_council'), "openClassCouncilModal(#{unity_id}, #{classroom_id}); return false;"),
      details_link
    ].compact

    dropdown_items = [
      content_tag(:li) do
        link_to t('pedagogical_trackings.index.resume_entries'), '#',
                onclick: "openResumeModal(#{unity_id}, #{classroom_id}); return false;"
      end,
      content_tag(:li) do
        link_to t('pedagogical_trackings.index.absent_students'), '#',
                onclick: "openFrequencyReportModal(#{unity_id}, #{classroom_id}); return false;"
      end,
      content_tag(:li) do
        link_to t('pedagogical_trackings.index.class_council'), '#',
                onclick: "openClassCouncilModal(#{unity_id}, #{classroom_id}); return false;"
      end
    ]

    if details_link
      dropdown_items << content_tag(:li, '', class: 'divider')
      dropdown_items << content_tag(:li) { render_details_link(record, class: '') }
    end

    content_tag(:div, class: 'pedagogical-actions') do
      safe_join([
        content_tag(:div, class: 'pedagogical-actions__buttons') do
          safe_join(desktop_actions)
        end,
        content_tag(:div, class: 'btn-group pedagogical-actions__dropdown') do
          safe_join([
            content_tag(
              :button,
              safe_join([
                t('pedagogical_trackings.index.actions'),
                ' ',
                content_tag(:span, '', class: 'caret')
              ]),
              type: 'button',
              class: 'btn btn-primary btn-sm dropdown-toggle',
              data: { toggle: 'dropdown' },
              'aria-expanded': 'false'
            ),
            content_tag(:ul, class: 'dropdown-menu dropdown-menu-right') do
              safe_join(dropdown_items)
            end
          ])
        end
      ])
    end
  end

  def format(date)
    return '' if date.blank? || (date.respond_to?(:empty?) && date.empty?)
    date.strftime('%d/%m/%Y')
  end

  private

  def action_button(label, onclick)
    content_tag(
      :button,
      label,
      type: 'button',
      class: 'btn btn-primary btn-sm pedagogical-action-btn',
      onclick: onclick
    )
  end
end
