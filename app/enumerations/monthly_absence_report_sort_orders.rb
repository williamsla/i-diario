class MonthlyAbsenceReportSortOrders < EnumerateIt::Base
  associate_values :student_name, :absences_count

  sort_by :translation
end
