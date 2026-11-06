class DashboardController < ApplicationController
  def index
    if student_portal_user?
      @report_card = StudentReportCard.build(current_user.student, classroom_id: params[:classroom_id])
      return
    end

    fill_in_school_calendar_select_options
    fetch_current_school_calendar_step if @school_calendar_steps_options.any?
  end

  private

  def fill_in_school_calendar_select_options
    @school_calendar_steps_options = []
    current_school_calendar_steps.each do |school_calendar_step|
      option = []
      option << school_calendar_step.to_s
      option << school_calendar_step.id
      @school_calendar_steps_options << option
    end
  end

  def fetch_current_school_calendar_step
    return if current_user_classroom.blank?
    @current_school_calendar_step = steps_fetcher.step_by_date(Time.zone.today).try(:id)
  end

  def current_school_calendar_steps
    return [] if current_user_classroom.blank?

    steps_fetcher.steps
  end

  def steps_fetcher
    @steps_fetcher ||= StepsFetcher.new(current_user_classroom)
  end
end
