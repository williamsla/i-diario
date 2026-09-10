$(function () {
  window.classrooms = [];
  window.disciplines = [];

  var $hideWhenGlobalAbsence = $(".hide-when-global-absence"),
    $globalAbsence = $("#discipline_lesson_plan_report_form_global_absence"),
    $examRuleNotFoundAlert = $('#exam-rule-not-found-alert'),
    $unity = $('#discipline_lesson_plan_report_form_unity_id'),
    $classroom = $('#discipline_lesson_plan_report_form_classroom_id'),
    $discipline = $('#discipline_lesson_plan_report_form_discipline_id'),
    $student = $('#discipline_lesson_plan_report_form_student_id'),
    $studentField = $('#individual-student-field'),
    flashMessages = new FlashMessages();

  $unity.on('change', function () {
    clearFields();
    getClassrooms();
  });

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
    if (data.classrooms.length == 0) {
      blockFields();
      flashMessages.error('Não há turmas para a unidade selecionada.')
      return;
    }

    let classrooms = _.map(data.classrooms, function (classroom) {
      return { id: classroom.table.id, name: classroom.table.name, text: classroom.table.text };
    });

    $classroom.prop('readonly', false);
    $classroom.select2({ data: classrooms })
    // Define a primeira opção como selecionada por padrão
    $classroom.val(classrooms[0].id).trigger('change');
  }

  function handleFetchClassroomsError() {
    flashMessages.error('Ocorreu um erro ao buscar as turmas da escola selecionada.');
  }

  function fetchDisciplines(classroom_id) {
    if (_.isEmpty(window.disciplines)) {
      $.ajax({
        url: Routes.by_classroom_disciplines_pt_br_path({ classroom_id: classroom_id, format: 'json' }),
        success: handleFetchDisciplinesSuccess,
        error: handleFetchDisciplinesError
      });
    }
  };

  function handleFetchDisciplinesSuccess(data) {
    if (data.disciplines.length == 0) {
      blockFields();
      flashMessages.error('Não existem disciplinas para a turma selecionada.');
      return;
    } else {
      var selectedDisciplines = data.disciplines.map(function (discipline) {
        return { id: discipline.table.id, name: discipline.table.name, text: discipline.table.text };
      });

      $discipline.select2({ data: selectedDisciplines });
      // Define a primeira opção como selecionada por padrão
      $discipline.val(selectedDisciplines[0].id).trigger('change');
    }
  };

  function handleFetchDisciplinesError() {
    flashMessages.error('Ocorreu um erro ao buscar as disciplinas da turma selecionada.');
  };

  var fetchExamRule = function (params, callback) {
    $.getJSON('/exam_rules?' + $.param(params)).always(function (data) {
      callback(data);
    });
  };

  var checkExamRule = function (params) {
    fetchExamRule(params, function (exam_rule) {
      $('form input[type=submit]').removeClass('disabled');
      if (!$.isEmptyObject(exam_rule)) {
        $examRuleNotFoundAlert.addClass('hidden');

        if (exam_rule.frequency_type == 1) {
          $globalAbsence.val(1);
          $hideWhenGlobalAbsence.hide();
        } else {
          $globalAbsence.val(0);
          $hideWhenGlobalAbsence.show();
        }
      } else {
        $globalAbsence.val(0);
        $hideWhenGlobalAbsence.hide();

        // Display alert
        $examRuleNotFoundAlert.removeClass('hidden');

        // Disable form submit
        $('form input[type=submit]').addClass('disabled');
      }
    });
  }

  $classroom.on('change', function () {
    let classroom_id = $classroom.select2('val');
    var params = {
      classroom_id: classroom_id
    };

    window.disciplines = [];

    if (!_.isEmpty(params)) {
      $discipline.prop('readonly', false);
      checkExamRule(params);
      fetchDisciplines(classroom_id);
      fetchStudents(classroom_id);
    } else {
      clearStudents();
    }
  });

  if ($classroom.length && $classroom.val().length) {
    checkExamRule({ classroom_id: $classroom.val() });
  }

  function fetchStudents(classroom_id) {
    if (!$student.length || _.isEmpty(classroom_id)) {
      clearStudents();
      return;
    }

    $.ajax({
      url: Routes.fetch_students_discipline_lesson_plan_report_pt_br_path({
        classroom_id: classroom_id,
        format: 'json'
      }),
      success: handleFetchStudentsSuccess,
      error: handleFetchStudentsError
    });
  }

  function handleFetchStudentsSuccess(students) {
    if (!students || students.length === 0) {
      clearStudents();
      return;
    }

    var studentOptions = _.map(students, function (student) {
      return { id: student.id, name: student.name || student.text, text: student.text || student.name };
    });

    studentOptions.unshift({ id: 'empty', name: '<option></option>', text: '' });
    $student.select2({ data: studentOptions });
    $student.val('').trigger('change');
    $studentField.removeClass('hidden');
  }

  function handleFetchStudentsError() {
    clearStudents();
    flashMessages.error('Ocorreu um erro ao buscar os alunos com conteúdo individual da turma selecionada.');
  }

  function clearStudents() {
    if (!$student.length) {
      return;
    }

    $student.val('').select2({ data: [] });
    $studentField.addClass('hidden');
  }

  function clearFields() {
    $classroom.val('').select2({ data: [] });
    $discipline.val('').select2({ data: [] });
    clearStudents();
  }

  function blockFields() {
    $classroom.prop('readonly', true);
    $discipline.prop('readonly', true);
  }
});
