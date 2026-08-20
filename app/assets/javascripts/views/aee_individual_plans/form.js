$(function () {
  'use strict';

  var $student = $('#aee_individual_plan_student_id');
  var derivedFields = {
    age: $('#aee_individual_plan_age'),
    birth_date_label: $('#aee_individual_plan_birth_date_label')
  };
  var fields = {
    characteristics: $('#aee_individual_plan_characteristics'),
    identified_difficulties: $('#aee_individual_plan_identified_difficulties'),
    goals: $('#aee_individual_plan_goals'),
    resources: $('#aee_individual_plan_resources'),
    strategies: $('#aee_individual_plan_strategies'),
    monitoring: $('#aee_individual_plan_monitoring'),
    psychomotor_skills: $('#aee_individual_plan_psychomotor_skills'),
    cognitive_skills: $('#aee_individual_plan_cognitive_skills'),
    socioemotional_skills: $('#aee_individual_plan_socioemotional_skills'),
    linguistic_skills: $('#aee_individual_plan_linguistic_skills'),
    specialized_teacher_name: $('#aee_individual_plan_specialized_teacher_name'),
    aee_case_study_id: $('#aee_individual_plan_aee_case_study_id')
  };

  if (!$student.length) {
    return;
  }

  var fillFromPreviousDocuments = function (studentId) {
    if (!studentId) {
      return;
    }

    $.ajax({
      url: Routes.student_data_aee_individual_plans_pt_br_path({
        student_id: studentId,
        format: 'json'
      }),
      success: function (data) {
        var filled = false;

        $.each(derivedFields, function (key, $field) {
          if (!$field.length) {
            return;
          }

          $field.val(data[key] || '');
        });

        $.each(fields, function (key, $field) {
          if (!$field.length || $field.val() || !data[key]) {
            return;
          }

          $field.val(data[key]);
          filled = true;
        });

        if (filled) {
          $('.aee-prefill-notice').show();
        }
      }
    });
  };

  $student.on('change', function () {
    fillFromPreviousDocuments($student.select2('val'));
  });

  var initialStudentId = $student.select2('val') || $student.val();
  if (initialStudentId && !$('#aee_individual_plan_id').val()) {
    fillFromPreviousDocuments(initialStudentId);
  }
});
