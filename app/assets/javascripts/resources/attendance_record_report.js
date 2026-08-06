$(function () {
  window.classrooms = [];
  window.disciplines = [];
  const PERIOD_FULL = 4;

  var $disciplineField = $(".discipline-field"),
    $classNumbersField = $(".class-numbers-field"),
    $globalAbsence = $("#attendance_record_report_form_global_absence"),
    $unity = $("#attendance_record_report_form_unity_id"),
    $examRuleNotFoundAlert = $('#exam-rule-not-found-alert'),
    $selectAllClasses = $('#select-all-classes'),
    $deselectAllClasses = $('#deselect-all-classes'),
    $classroom = $('#attendance_record_report_form_classroom_id'),
    $discipline = $('#attendance_record_report_form_discipline_id'),
    $class_numbers = $('#attendance_record_report_form_class_numbers'),
    $showOnlyDisciplineDaysLabel = $('label[for="attendance_record_report_form_show_only_discipline_days"]'),
    flashMessages = new FlashMessages();

  var SHOW_DAYS_DISCIPLINE_LABEL = 'Exibir somente os dias de aulas da disciplina';
  var SHOW_DAYS_TEACHER_LABEL = 'Exibir somente os dias de aulas do professor';

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

  $classroom.on('change', function () {
    let classroom_id = $classroom.select2('val');
    var params = {
      classroom_id: classroom_id
    };

    $class_numbers.select2("val", "")

    if (!_.isEmpty(params)) {
      $discipline.prop('readonly', false);
      checkExamRule(params);
      fetchDisciplines(classroom_id);
    }

    toggleClassNumbersByFrequencyType();
  });

  var fetchExamRule = function (params, callback) {
    $.getJSON('/exam_rules?' + $.param(params)).always(function (data) {
      callback(data);
    });
  };

  var fetchFrequencyType = function (params, callback) {
    $.getJSON(Routes.frequency_type_attendance_record_report_pt_br_path(params)).always(function (data) {
      callback(data);
    });
  };

  var checkExamRule = function (params) {
    fetchExamRule(params, function (data) {
      var examRule = data.exam_rule;
      $('form input[type=submit]').removeClass('disabled');
      if (!$.isEmptyObject(examRule)) {
        $examRuleNotFoundAlert.addClass('hidden');
        if (examRule.frequency_type == 2 || examRule.allow_frequency_by_discipline) {
          $globalAbsence.val(0);
          $disciplineField.show();
        } else {
          $globalAbsence.val(1);
          $disciplineField.show();
          $classNumbersField.hide();
          $class_numbers.val("");
          $class_numbers.trigger("change");
        }

      } else {
        $globalAbsence.val(0);
        $disciplineField.hide();
        $classNumbersField.hide();

        // Display alert
        $examRuleNotFoundAlert.removeClass('hidden');

        // Disable form submit
        $('form input[type=submit]').addClass('disabled');
      }
    });
  }

  var toggleClassNumbersByFrequencyType = function () {
    var classroomId = $classroom.select2('val');
    var disciplineId = $discipline.select2('val');

    if (_.isEmpty(classroomId) || _.isEmpty(disciplineId)) {
      $classNumbersField.hide();
      $class_numbers.val("");
      $class_numbers.trigger("change");
      $selectAllClasses.show();
      $deselectAllClasses.hide();
      $showOnlyDisciplineDaysLabel.text(SHOW_DAYS_TEACHER_LABEL);
      return;
    }

    fetchFrequencyType({
      classroom_id: classroomId,
      discipline_id: disciplineId
    }, function (frequencyType) {
      var normalizedFrequencyType = parseInt(frequencyType, 10);

      if (normalizedFrequencyType === 2) {
        $classNumbersField.show();
        $showOnlyDisciplineDaysLabel.text(SHOW_DAYS_DISCIPLINE_LABEL);
      } else {
        $classNumbersField.hide();
        $class_numbers.val("");
        $class_numbers.trigger("change");
        $selectAllClasses.show();
        $deselectAllClasses.hide();
        $showOnlyDisciplineDaysLabel.text(SHOW_DAYS_TEACHER_LABEL);
      }
    });
  };

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

  function clearFields() {
    $classroom.val('').select2({ data: [] });
    $discipline.val('').select2({ data: [] });
  }

  function blockFields() {
    $classroom.prop('readonly', true);
    $discipline.prop('readonly', true);
  }

  $discipline.on('change', async function () {
    $('#attendance_record_report_form_period').select2('val', '');
    await getPeriod();
    toggleClassNumbersByFrequencyType();
  });

  async function getPeriod() {
    let classroom_id = $('#attendance_record_report_form_classroom_id').select2('val');
    let discipline_id = $('#attendance_record_report_form_discipline_id').select2('val');

    if (!_.isEmpty(classroom_id)) {
      return $.ajax({
        url: Routes.period_attendance_record_report_pt_br_path({
          classroom_id: classroom_id,
          discipline_id: discipline_id,
          format: 'json'
        }),
        success: handleFetchPeriodByClassroomSuccess,
        error: handleFetchPeriodByClassroomError
      });
    }
  }

  function handleFetchPeriodByClassroomSuccess(data) {
    let period = $('#attendance_record_report_form_period');
    var payload = (data && typeof data === 'object' && !Array.isArray(data)) ? data : { period: data };
    var periodValue = payload.period;
    var requiresPeriodSelection = !!payload.requires_period_selection;

    // Turma integral OU professor com a disciplina em mais de um turno: permite escolher o período.
    if (requiresPeriodSelection || periodValue == PERIOD_FULL) {
      period.attr('readonly', false);
      if (requiresPeriodSelection) {
        period.select2('val', '');
      }
      return;
    }

    getNumberOfClasses();
    period.select2('val', periodValue);
    period.attr('readonly', true);
  };

  function handleFetchPeriodByClassroomError() {
    flashMessages.error('Ocorreu um erro ao buscar o período da turma.');
  };

  function getNumberOfClasses() {
    let classroom_id = $('#attendance_record_report_form_classroom_id').select2('val');

    $.ajax({
      url: Routes.number_of_classes_attendance_record_report_pt_br_path({
        classroom_id: classroom_id,
        format: 'json'
      }),
      success: handleFetchNumberOfClassesByClassroomSuccess,
      error: handleFetchNumberOfClassesByClassroomError
    });
  }

  function handleFetchNumberOfClassesByClassroomSuccess(data) {
    var elements = []

    for (let i = 1; i <= data; i++) {
      elements.push({ id: i, name: i, text: i })
    }

    $class_numbers.select2('data', elements);
  }

  function handleFetchNumberOfClassesByClassroomError() {
    flashMessages.error('Ocorreu um erro ao buscar os numeros de aula da turma.');
  }

  $selectAllClasses.on('click', function () {
    var allElements = $.parseJSON($("#attendance_record_report_form_class_numbers").attr('data-elements'));
    var joinedElements = "";

    $.each(allElements, function (index, element) {
      joinedElements = joinedElements + element.name + ",";
    });

    $class_numbers.val(joinedElements);
    $class_numbers.trigger("change");

    $selectAllClasses.hide();
    $deselectAllClasses.show();
  });

  $deselectAllClasses.on('click', function () {

    $class_numbers.val("");
    $class_numbers.trigger("change");

    $selectAllClasses.show();
    $deselectAllClasses.hide();
  });

  $disciplineField.hide();
  $classNumbersField.hide();

  // Se houver valor inicial em class_numbers, seleciona automaticamente
  if ($class_numbers.length && $class_numbers.val() && $class_numbers.val().length > 0) {
    var initialValue = $class_numbers.val();
    $class_numbers.val(initialValue);
    $class_numbers.trigger("change");
    $selectAllClasses.hide();
    $deselectAllClasses.show();
  }

  if ($classroom.length && $classroom.val().length) {
    checkExamRule({ classroom_id: $classroom.val() });
  }

  if ($discipline.length && $discipline.val().length) {
    toggleClassNumbersByFrequencyType();
  }

  $('form').submit(function (event) {
    var tempoEspera = 2000;

    // Define um timeout para habilitar o botão após o tempo de espera
    setTimeout(function () {
      $('#send-form').prop('disabled', false);
    }, tempoEspera);
  });
});
