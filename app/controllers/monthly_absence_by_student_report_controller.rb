class MonthlyAbsenceByStudentReportController < ApplicationController
  def form
    @monthly_absence_by_student_report_form = MonthlyAbsenceByStudentReportForm.new(
      unity_id: current_unity.id,
      year: current_school_year,
      sort_by: MonthlyAbsenceReportSortOrders::STUDENT_NAME
    )

    set_options_by_user
  end

  def report
    @monthly_absence_by_student_report_form = MonthlyAbsenceByStudentReportForm.new(resource_params)

    if @monthly_absence_by_student_report_form.valid?
      pdf_report = MonthlyAbsenceByStudentReport.build(
        current_entity_configuration,
        @monthly_absence_by_student_report_form
      )

      send_pdf(t('routes.monthly_absence_by_student'), pdf_report.render)
    else
      set_options_by_user
      render :form
    end
  end

  private

  def resource_params
    params.require(:monthly_absence_by_student_report_form).permit(
      :unity_id,
      :year,
      :months,
      :grade_id,
      :classroom_id,
      :sort_by
    )
  end

  def set_options_by_user
    @admin_or_employee ||= current_user.current_role_is_admin_or_employee?
    @unities ||= @admin_or_employee ? Unity.ordered : [current_user_unity]

    unity_id = @monthly_absence_by_student_report_form.unity_id
    school_year = @monthly_absence_by_student_report_form.year.presence || current_school_year

    return unless unity_id.present?

    @grades = Grade.by_unity(unity_id).by_year(school_year).ordered
    @classrooms = Classroom.by_unity(unity_id).by_year(school_year).ordered

    return unless @monthly_absence_by_student_report_form.grade_id.present?

    @classrooms = @classrooms.by_grade(@monthly_absence_by_student_report_form.grade_id)
  end
end
