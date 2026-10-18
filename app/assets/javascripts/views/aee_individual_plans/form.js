$(function () {
  'use strict';

  var $student = $('#aee_individual_plan_student_id');
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

  var updateIdentification = function (data) {
    var age = (data && data.age) || '';
    var birthDate = (data && data.birth_date_label) || '';

    $('#aee_individual_plan_age').text(age);
    $('#aee-pei-age-item').toggle(!!age);
    $('#aee_individual_plan_birth_date_label').text(birthDate);
    $('#aee-pei-birth-item').toggle(!!birthDate);
  };

  var updateCaseStudy = function (caseStudy) {
    var $action = $('#aee-case-study-action');

    if (!$action.length) {
      return;
    }

    if (!caseStudy || !caseStudy.present) {
      $action.hide();
      $('#aee-case-study-summary').text('');
      $('#aee-case-study-sections').empty();
      return;
    }

    $('#aee-case-study-summary').text(caseStudy.summary || '');

    var $sections = $('#aee-case-study-sections').empty();

    $.each(caseStudy.sections || [], function (_, section) {
      $sections.append($('<h5>').text(section.label || ''));
      $sections.append($('<p>').css('white-space', 'pre-wrap').text(section.text || ''));
    });

    $action.show();
  };

  var fillFromPreviousDocuments = function (studentId) {
    if (!studentId) {
      updateIdentification(null);
      updateCaseStudy(null);
      return;
    }

    $.ajax({
      url: Routes.student_data_aee_individual_plans_pt_br_path({
        student_id: studentId,
        format: 'json'
      }),
      success: function (data) {
        if (data.existing_id) {
          window.location = Routes.edit_aee_individual_plan_pt_br_path(data.existing_id);
          return;
        }

        updateIdentification(data);
        updateCaseStudy(data.case_study);

        var filled = false;

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

  $('#view-aee-case-study').on('click', function (event) {
    event.preventDefault();
  });

  $student.on('change', function () {
    fillFromPreviousDocuments($student.select2('val'));
  });

  var initialStudentId = $student.select2('val') || $student.val();
  if (initialStudentId && !$('#aee_individual_plan_id').val()) {
    fillFromPreviousDocuments(initialStudentId);
  }
});
