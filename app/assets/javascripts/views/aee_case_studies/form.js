$(function () {
  'use strict';

  var $student = $('#aee_case_study_student_id');
  var $identification = $('#aee_case_study_identification');
  var $summary = $('#aee-student-summary');
  var emptyLabel = $summary.data('empty') || '—';

  if (!$student.length) {
    return;
  }

  function summaryValue(value) {
    return value || emptyLabel;
  }

  function fillSummary(data) {
    $summary.find('[data-summary="age"]').text(summaryValue(data.age));
    $summary.find('[data-summary="grade_stage"]').text(summaryValue(data.grade_stage));
    $summary.find('[data-summary="modality"]').text(summaryValue(data.modality));
  }

  function showSummary() {
    $summary.removeAttr('hidden').removeClass('is-empty');
  }

  function hideSummary() {
    fillSummary({});
    $summary.attr('hidden', 'hidden').addClass('is-empty');
  }

  $student.on('change', function () {
    var studentId = $student.select2('val');

    if (!studentId) {
      hideSummary();
      $identification.val('');
      return;
    }

    $.ajax({
      url: Routes.student_data_aee_case_studies_pt_br_path({
        student_id: studentId,
        format: 'json'
      }),
      success: function (data) {
        fillSummary(data);
        showSummary();
        $identification.val(data.identification || '');
      }
    });
  });
});
