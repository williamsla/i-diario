# frozen_string_literal: true

module AeeContentRecordSupport
  extend ActiveSupport::Concern

  def student_data
    return render json: {} unless is_aee

    authorize controller_name.classify.constantize, :new?

    student = Student.find_by(id: params[:student_id])
    return render json: {} if student.blank?

    render json: AeePrefill.content_record_from_pei(
      student: student,
      classroom: current_user_classroom,
      year: current_user_school_year
    )
  end
end
