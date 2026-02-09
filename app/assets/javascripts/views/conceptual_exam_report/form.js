$(function () {
  'use strict';

  var $classroom = $('#conceptual_exam_report_form_classroom_id');
  var $step = $('#conceptual_exam_report_form_step_id');
  var flashMessages = new FlashMessages();

  $classroom.on('change', function () {
    getStep();
  });

  function getStep() {
    var classroom_id = $classroom.select2('val');
    if (!_.isEmpty(classroom_id)) {
      $.ajax({
        url: Routes.fetch_step_conceptual_exam_report_path({
          classroom_id: classroom_id,
          format: 'json'
        }),
        success: handleFetchStepByClassroomSuccess,
        error: handleFetchStepByClassroomError
      });
    }
  }

  function handleFetchStepByClassroomSuccess(data) {
    var selectedSteps = data.map(function (step) {
      return { id: step.id, text: step.description, start_at: step.start_at, end_at: step.end_at };
    });
    $step.select2({ data: selectedSteps });
    if (selectedSteps.length > 0) {
      $step.val(selectedSteps[0].id).trigger('change');
    }
  }

  function handleFetchStepByClassroomError() {
    flashMessages.error('Ocorreu um erro ao buscar a etapa da turma.');
  }
});
