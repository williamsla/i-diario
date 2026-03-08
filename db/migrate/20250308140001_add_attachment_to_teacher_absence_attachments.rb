# frozen_string_literal: true

class AddAttachmentToTeacherAbsenceAttachments < ActiveRecord::Migration[5.0]
  def change
    add_column :teacher_absence_attachments, :attachment, :string
    add_column :teacher_absence_attachments, :attachment_file_name_with_hash, :string
  end
end
