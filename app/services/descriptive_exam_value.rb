module DescriptiveExamValue
  module_function

  def present?(value)
    return false if value.nil?

    text = value.to_s
    text = text.gsub(/contenteditable\s*=\s*["'][^"']*["']/i, '')
    text = ActionView::Base.full_sanitizer.strip_tags(text)
    text = CGI.unescapeHTML(text)
    text = text.gsub(/&nbsp;/i, ' ')
               .gsub(/\u00a0/, '')
               .gsub(/[\u200b-\u200d\ufeff]/, '')
               .squish

    text.present?
  end

  def blank?(value)
    !present?(value)
  end
end
