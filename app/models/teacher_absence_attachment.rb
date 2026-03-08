# frozen_string_literal: true

class TeacherAbsenceAttachment < ApplicationRecord
  belongs_to :teacher_absence

  mount_uploader :attachment, DocUploader

  delegate :filename, to: :attachment
end
