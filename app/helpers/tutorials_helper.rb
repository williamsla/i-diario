module TutorialsHelper
  YOUTUBE_ID_PATTERN = %r{
    (?:youtube\.com/(?:watch\?v=|embed/)|youtu\.be/)
    ([A-Za-z0-9_-]{6,})
  }x.freeze

  def tutorial_embed_url(video)
    return video['url'] if video['url'].present?

    youtube_id = extract_youtube_id(video['external_url'])
    return if youtube_id.blank?

    "https://www.youtube.com/embed/#{youtube_id}"
  end

  def tutorial_playable?(video)
    tutorial_embed_url(video).present?
  end

  private

  def extract_youtube_id(url)
    return if url.blank?

    match = url.to_s.match(YOUTUBE_ID_PATTERN)
    match && match[1]
  end
end
