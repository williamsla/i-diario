class StudentEnrollmentsListsController < ApplicationController
  before_action :adjusted_period
  before_action :validate_date_param, only: :by_date

  def by_date
    student_enrollments = StudentEnrollmentsList.new(
      classroom: params[:filter][:classroom],
      discipline: params[:filter][:discipline],
      score_type: params[:filter][:score_type],
      opinion_type: params[:filter][:opinion_type],
      show_inactive: ActiveRecord::Type::Boolean.new.type_cast_from_user(params[:filter][:show_inactive]),
      with_recovery_note_in_step: ActiveRecord::Type::Boolean.new.type_cast_from_user(
        params[:filter][:with_recovery_note_in_step]
      ),
      date: params[:filter][:date],
      period: @period
    ).student_enrollments

    render json: student_enrollments
  end

  def by_date_range
    student_enrollments = StudentEnrollmentsList.new(
      classroom: params[:filter][:classroom],
      discipline: params[:filter][:discipline],
      start_at: params[:filter][:start_at],
      end_at: params[:filter][:end_at],
      score_type: params[:filter][:score_type],
      opinion_type: params[:filter][:opinion_type],
      search_type: :by_date_range,
      show_inactive: ActiveRecord::Type::Boolean.new.type_cast_from_user(params[:filter][:show_inactive]),
      period: @period
    ).student_enrollments

    render json: student_enrollments
  end

  private

  def validate_date_param
    validator = DateParamValidator.new(params[:filter][:date])

    return if validator.valid?

    render json: { errors: validator.errors.full_messages }, status: :unprocessable_entity
  end

  def current_teacher_period
    if current_user.current_role_is_admin_or_employee?
      TeacherPeriodFetcher.new(
        current_teacher.id,
        current_user.current_classroom_id,
        current_user.current_discipline_id
      ).teacher_period
    else
      TeacherPeriodFetcher.new(
        current_teacher.id,
        params[:filter][:classroom],
        params[:filter][:discipline],
      ).teacher_period
    end
  end

  def adjusted_period
    teacher_period = current_teacher_period
    @period = teacher_period != Periods::FULL.to_i ? teacher_period : nil
  end
end
