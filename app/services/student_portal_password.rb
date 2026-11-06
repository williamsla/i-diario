class StudentPortalPassword
  def self.for(name:, cpf:)
    new(name, cpf).to_s
  end

  def initialize(name, cpf)
    @name = name
    @cpf = cpf
  end

  def to_s
    return if first_name.blank? || digits.blank?

    suffix_size = first_name.length == 1 ? 4 : 3
    suffix = digits.first(suffix_size)
    return if suffix.length < suffix_size

    "#{first_name}@#{suffix}"
  end

  private

  def first_name
    token = @name.to_s.strip.split(/[[:space:]-]+/).first.to_s
    I18n.transliterate(token).downcase.gsub(/[^a-z]/, '')
  end

  def digits
    @digits ||= @cpf.to_s.gsub(/\D/, '')
  end
end
