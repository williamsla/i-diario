# frozen_string_literal: true

class OptionalHolidayAttachment < ApplicationRecord
  belongs_to :optional_holiday

  mount_uploader :attachment, DocUploader

  delegate :filename, to: :attachment
end
