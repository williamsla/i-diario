$(function () {
  'use strict';

  var $student = $('#aee_case_study_student_id');
  var $age = $('#aee_case_study_age');
  var $gradeStage = $('#aee_case_study_grade_stage');
  var $identification = $('#aee_case_study_identification');
  var $modality = $('#aee_case_study_modality');

  if (!$student.length) {
    return;
  }

  $student.on('change', function () {
    var studentId = $student.select2('val');

    if (!studentId) {
      return;
    }

    $.ajax({
      url: Routes.student_data_aee_case_studies_pt_br_path({
        student_id: studentId,
        format: 'json'
      }),
      success: function (data) {
        $age.val(data.age || '');

        if (!$gradeStage.val()) {
          $gradeStage.val(data.grade_stage || '');
        }

        if (!$identification.val()) {
          $identification.val(data.identification || '');
        }

        if (!$modality.val()) {
          $modality.val(data.modality || '');
        }
      }
    });
  });
});
