$(function () {
  'use strict';

  var $formElement = $('#aee_attendance_records_form');
  if ($formElement.length && typeof UnsavedChangesGuard !== 'undefined') {
    UnsavedChangesGuard.watch($formElement, {
      title: 'Deseja salvar este registro de atendimento antes de sair?',
      message: 'Você fez alterações no registro de atendimento AEE que ainda não foram salvas. ' +
               'Se sair agora, suas alterações serão perdidas.'
    });
  }

  var $student = $('#aee_attendance_record_student_id');
  var $planId = $('#aee_attendance_record_aee_individual_plan_id');
  var $duration = $('#aee_attendance_record_duration');
  var $objectives = $('#aee_attendance_record_session_objectives');
  var $context = $('#aee-pei-context');
  var $contextBody = $('#aee-pei-context-body');

  if (!$student.length) {
    return;
  }

  var escapeHtml = function (value) {
    return $('<div>').text(value || '').html();
  };

  var sectionHtml = function (title, value) {
    if (!value) {
      return '';
    }

    return '<p><strong>' + escapeHtml(title) + ':</strong> ' + escapeHtml(value) + '</p>';
  };

  var showContext = function (data) {
    if (!$context.length) {
      return;
    }

    if (!data || !data.has_pei) {
      $context.hide();
      return;
    }

    $contextBody.html(
      sectionHtml($context.data('goals-label'), data.pei_goals) +
      sectionHtml($context.data('strategies-label'), data.pei_strategies) +
      sectionHtml($context.data('resources-label'), data.pei_resources)
    );
    $context.show();
  };

  var fillFromPei = function (studentId) {
    if (!studentId) {
      $context.hide();
      return;
    }

    $.ajax({
      url: Routes.student_data_aee_attendance_records_pt_br_path({
        student_id: studentId,
        format: 'json'
      }),
      success: function (data) {
        var filled = false;

        if ($planId.length && !$planId.val() && data.aee_individual_plan_id) {
          $planId.val(data.aee_individual_plan_id);
        }

        if ($duration.length && !$duration.val() && data.duration) {
          $duration.val(data.duration);
          filled = true;
        }

        if ($objectives.length && !$objectives.val() && data.session_objectives) {
          $objectives.val(data.session_objectives);
          filled = true;
        }

        showContext(data);

        if (filled) {
          $('.aee-prefill-notice').show();
        }
      }
    });
  };

  $student.on('change', function () {
    fillFromPei($student.select2('val'));
  });

  var initialStudentId = $student.select2('val') || $student.val();
  if (initialStudentId && !$('#aee_attendance_record_id').val()) {
    fillFromPei(initialStudentId);
  }
});
