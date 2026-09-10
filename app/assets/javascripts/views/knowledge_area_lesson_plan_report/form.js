$(function () {
  "use strict"

  var $classroom = $('#knowledge_area_lesson_plan_report_form_classroom_id'),
    $unity = $('#knowledge_area_lesson_plan_report_form_unity_id'),
    $knowledge_area = $('#knowledge_area_lesson_plan_report_form_knowledge_area_id'),
    $student = $('#knowledge_area_lesson_plan_report_form_student_id'),
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
      flashMessages.error('Não há turmas para a unidade selecionada.')
      return;
    }

    let classrooms = _.map(data.classrooms, function (classroom) {
      return { id: classroom.table.id, name: classroom.table.name, text: classroom.table.text };
    });

    $classroom.select2({ data: classrooms })
    // Define a primeira opção como selecionada por padrão
    $classroom.val(classrooms[0].id).trigger('change');
  }

  function handleFetchClassroomsError() {
    flashMessages.error('Ocorreu um erro ao buscar as turmas da escola selecionada.');
  }

  $classroom.on('change', async function () {
    var classroom_id = $classroom.select2('val');

    if (!_.isEmpty(classroom_id)) {
      fetchKnowledgeArea(classroom_id);
      fetchStudents(classroom_id);
    } else {
      $knowledge_area.val('').trigger('change');
      clearStudents();
    }
  });

  function fetchKnowledgeArea(classroom_id) {
    $.ajax({
      url: Routes.fetch_knowledge_areas_knowledge_area_lesson_plan_report_pt_br_path({
        classroom_id: classroom_id,
        format: 'json'
      }),
      success: handleFetchKnowledgeAreaSuccess,
      error: handleFetchKnowledgeAreaError
    });
  };

  function handleFetchKnowledgeAreaSuccess(knowledge_area) {
    if (knowledge_area.length == 0) {
      flashMessages.error('Não há áreas de conhecimento para a turma selecionada.');
      return;
    }

    var selectedKnownledgeAreaSuccess = _.map(knowledge_area, function (knowledge_area) {
      return { id: knowledge_area['id'], text: knowledge_area['description'] };
    });

    $knowledge_area.select2({ data: selectedKnownledgeAreaSuccess });

    // Define a primeira opção como selecionada por padrão
    $knowledge_area.val(selectedKnownledgeAreaSuccess[0].id).trigger('change');
  };

  function handleFetchKnowledgeAreaError() {
    flashMessages.error('Ocorreu um erro ao buscar as áreas de conhecimento da turma selecionada.');
  };

  function fetchStudents(classroom_id) {
    $.ajax({
      url: Routes.fetch_students_knowledge_area_lesson_plan_report_pt_br_path({
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
    $student.val('').select2({ data: [] });
    $studentField.addClass('hidden');
  }

  $('#lesson-plan-report').on('click', function (e) {
    e.preventDefault();
    $('#knowledge-area-lesson-plan-report-form').attr('action',
      Routes.knowledge_area_lesson_plan_report_pt_br_path()
    );
    $('#knowledge-area-lesson-plan-report-form').submit();
  });

  $('#content-record-report').on('click', function (e) {
    e.preventDefault();
    $('#knowledge-area-lesson-plan-report-form').attr('action',
      Routes.knowledge_area_content_record_report_pt_br_path()
    );
    $('#knowledge-area-lesson-plan-report-form').submit();
  });

  function clearFields() {
    $classroom.val('').select2({ data: [] });
    $knowledge_area.val('').select2({ data: [] });
    clearStudents();
  }

  // Carrega as áreas de conhecimento quando a página carrega com uma turma já selecionada
  setTimeout(function() {
    var initialClassroomId = $classroom.select2('val');
    if (!_.isEmpty(initialClassroomId)) {
      fetchKnowledgeArea(initialClassroomId);
    }
  }, 100);
});
