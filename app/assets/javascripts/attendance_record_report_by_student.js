$(function () {
  'use strict';
  const PERIOD_FULL = 4;
  let flashMessages = new FlashMessages(),
      $unity = $('#attendance_record_report_by_student_form_unity_id'),
      $classroom = $('#attendance_record_report_by_student_form_classroom_id'),
      $period = $('#attendance_record_report_by_student_form_period');

  $(document).ready(function() {
    getClassrooms();
    initializeForm();
  });

  $unity.on('change', function () {
    $classroom.val('').select2({ data: [] });
    getClassrooms();
  });

  function initializeForm() {
    if ($unity.val() === '' || $classroom.val() === '') {
      $('#send-form').attr("disabled", true);
    }

  }

  function getClassrooms() {
    const unity_id = $unity.select2('val');

    if (!_.isEmpty(unity_id)) {
      $.ajax({
        url: Routes.by_unity_classrooms_pt_br_path({
          unity_id: unity_id,
          format: 'json'
        }),
        success: handleFetchClassroomsSuccess,
        error: handleFetchClassroomsError
      });
    }
  }

  function handleFetchClassroomsSuccess(data) {
    let classrooms = _.map(data.classrooms, function(classroom) {
      return { id: classroom.table.id, name: classroom.table.name, text: classroom.table.text };
    });
    classrooms.unshift({ id: 'all', name: '<option>Todas</option>', text: 'Todas' });
    $classroom.select2({ data: classrooms })
  }

  function handleFetchClassroomsError() {
    flashMessages.error('Ocorreu um erro ao buscar as turmas da escola selecionada.');
  }

  $classroom.on('change', function() {
    if ($unity.val() !== '' && $classroom.val() !== '') {
      $('#send-form').attr("disabled", false);
    }
    getPeriod();
  });

  function getPeriod() {
    const classroom_id = $classroom.select2('val');
    let periodOptions = [{ id: 'all', name: '<option>Todas</option>', text: 'Todas' }];

    if (!_.isEmpty(classroom_id)) {
      if (classroom_id === 'all') {
        $period.val('all')
        $period.select2({ data: periodOptions, val: ['all'] })
      } else {
        $.ajax({
          url: Routes.fetch_period_by_classroom_attendance_record_report_by_students_pt_br_path({
            classroom_id: classroom_id,
            format: 'json'
          }),
          success: handleFetchPeriodSuccess,
          error: handleFetchPeriodError
        });
      }
    }
  }

  function handleFetchPeriodSuccess(data) {
    if (data != PERIOD_FULL) {
      $period.select2('val', data);
      $period.attr('readonly', true)
    } else {
      $period.attr('readonly', false)
    }

    $period.select2({ data: selectedPeriod });
  }

  function handleFetchPeriodError(data) {
    flashMessages.error('Ocorreu um erro ao buscar o período da turma selecionada.');
  }

});
