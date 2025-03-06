module PedagogicalTrackingsHelper
  def render_details_link(record)
    if (classroom_id = record.classroom_id.presence)
      link_to(
        'Ver professores',
        '#',
        class: 'btn btn-info open_classroom_detail_modal',
        data: { classroom_id: classroom_id }
      )
    else
      link_to(
        'Ver turmas',
        link_params(record),
        class: 'btn btn-info'
      )
    end
  end

  def link_params(record)
    {
      'search[unity_id]': record.unity_id,
      'search[start_date]': format(record.start_date),
      'search[end_date]': format(record.end_date)
    }
  end

  def format(date)
    return '' if date.empty?
    date.strftime('%d/%m/%Y')
  end
end
