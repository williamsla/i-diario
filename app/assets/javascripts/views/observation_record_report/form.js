$(function () {
  'use strict';

  let flashMessages = new FlashMessages();
  let $unity = $('#observation_record_report_form_unity_id');
  let $classroom = $('#observation_record_report_form_classroom_id');
  let $discipline = $('#observation_record_report_form_discipline_id');
  let $student = $('#observation_record_report_form_student_id');

  $(document).ready(function() {
    getClassrooms();
  });

  $unity.on('change', function () {
    clearFields();
    getClassrooms();
  });

  $classroom.on('change', function() {
    $discipline.val('').select2({ data: [] });
    $student.val('').select2({ data: [] });
    getDisciplines();
    getStudents();
    toggleSubmit();
  });

  $discipline.on('change', function() {
    toggleSubmit();
  });

  function toggleSubmit() {
    var classroomSelected = $classroom.val() !== '' && $classroom.val() !== null;
    var disciplineSelected = $discipline.val() !== '' && $discipline.val() !== null;
    $('#btn-submit').attr('disabled', !(classroomSelected && disciplineSelected));
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

    var currentValue = $classroom.val();
    $classroom.select2({ data: classrooms });
    if (!_.isEmpty(currentValue)) {
      $classroom.select2('val', currentValue);
    }
    getDisciplines();
    getStudents();
    toggleSubmit();
  }

  function handleFetchClassroomsError() {
    flashMessages.error('Ocorreu um erro ao buscar as turmas da escola selecionada.');
  }

  function getDisciplines() {
    const classroom_id = $classroom.select2('val');

    if (_.isEmpty(classroom_id)) {
      $discipline.select2({ data: [] });
      return;
    }

    if (classroom_id === 'all') {
      var allOption = [{ id: 'all', name: '<option>Todas</option>', text: 'Todas' }];
      $discipline.select2({ data: allOption });
      $discipline.select2('val', 'all');
      toggleSubmit();
      return;
    }

    $.ajax({
      url: Routes.by_classroom_disciplines_pt_br_path({ classroom_id: classroom_id, format: 'json' }),
      success: handleFetchDisciplinesSuccess,
      error: handleFetchDisciplinesError
    });
  }

  function handleFetchDisciplinesSuccess(data) {
    let selectedDisciplines = _.map(data.disciplines || data, function(discipline) {
      if (discipline.table) {
        return { id: discipline.table.id, name: discipline.table.name, text: discipline.table.text };
      }
      return { id: discipline.id, name: discipline.description || discipline.name, text: discipline.description || discipline.name || discipline.text };
    });

    selectedDisciplines.unshift({ id: 'all', name: '<option>Todas</option>', text: 'Todas' });

    var currentValue = $discipline.val() || 'all';
    $discipline.select2({ data: selectedDisciplines });
    $discipline.select2('val', currentValue);
    toggleSubmit();
  }

  function handleFetchDisciplinesError() {
    flashMessages.error('Ocorreu um erro ao buscar as disciplinas da turma selecionada.');
  }

  function getStudents() {
    const classroom_id = $classroom.select2('val');

    $student.select2({ data: [] });

    if (_.isEmpty(classroom_id) || classroom_id === 'all') {
      $student.select2({ data: [{ id: 'all', name: '<option>Todos</option>', text: 'Todos' }] });
      $student.select2('val', 'all');
      return;
    }

    var today = new Date();
    var dateParam = ('0' + today.getDate()).slice(-2) + '/' +
                    ('0' + (today.getMonth() + 1)).slice(-2) + '/' +
                    today.getFullYear();

    $.ajax({
      url: Routes.classroom_students_pt_br_path({
        classroom_id: classroom_id,
        date: dateParam,
        format: 'json'
      }),
      success: handleFetchStudentsSuccess,
      error: handleFetchStudentsError
    });
  }

  function handleFetchStudentsSuccess(data) {
    var list = data.students || data || [];
    var students = _.map(list, function(student) {
      return { id: student.id, text: student.name };
    });

    students.unshift({ id: 'all', name: '<option>Todos</option>', text: 'Todos' });

    var currentValue = $student.val() || 'all';
    $student.select2({ data: students });
    $student.select2('val', currentValue);
  }

  function handleFetchStudentsError() {
    flashMessages.error('Ocorreu um erro ao buscar os alunos da turma selecionada.');
  }

  function clearFields() {
    $classroom.val('').select2({ data: [] });
    $discipline.val('').select2({ data: [] });
    $student.val('').select2({ data: [] });
    toggleSubmit();
  }
});
