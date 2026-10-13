class PostingDateValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return unless value && record.classroom

    checker = PostingDateChecker.new(record.classroom, value)

    unless checker.check
      record.errors.add(attribute, checker.not_allowed_message)
    end
  end
end
