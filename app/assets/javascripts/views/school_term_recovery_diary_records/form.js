$(function () {
  'use strict';

  let flashMessages = new FlashMessages();
  let examRule = null;
  let $unity = $('#school_term_recovery_diary_record_recovery_diary_record_attributes_unity_id');
  let $classroom = $('#school_term_recovery_diary_record_recovery_diary_record_attributes_classroom_id');
  let $discipline = $('#school_term_recovery_diary_record_recovery_diary_record_attributes_discipline_id');
  let $step = $('#school_term_recovery_diary_record_step_id');
  let $recorded_at = $('#school_term_recovery_diary_record_recorded_at');
  let $submitButton = $('input[type=submit]');
  /** Evita limpar data ao hidratar select2 de disciplina/etapa no carregamento (edição). */
  var suppressRecordedAtOnDisciplineChange = false;

  function getUnityId() {
    if (!$unity.length) return null;
    if ($unity.is('select') && $unity.data('select2')) return $unity.select2('val');
    return $unity.val();
  }

  function getClassroomId() {
    if (!$classroom.length) return null;
    if ($classroom.is('select') && $classroom.data('select2')) return $classroom.select2('val');
    return $classroom.val();
  }

  function getDisciplineId() {
    if (!$discipline.length) return null;
    if ($discipline.is('select') && $discipline.data('select2')) return $discipline.select2('val');
    return $discipline.val();
  }

  async function loadClassroomDependencies(classroom_id, clearRecordedAt) {
    if (_.isEmpty(classroom_id)) {
      $discipline.select2({ data: [] }).trigger('change');
      $step.select2({ data: [] }).trigger('change');
      return;
    }

    suppressRecordedAtOnDisciplineChange = true;
    try {
      await getStep(classroom_id);
      await getNumberOfDecimalPlaces(classroom_id);
      await fetchDisciplines(classroom_id);
    } finally {
      suppressRecordedAtOnDisciplineChange = false;
    }

    if (clearRecordedAt) {
      $recorded_at.val(null).trigger('change');
    }
  }

  $classroom.on('change', async function () {
    await loadClassroomDependencies(getClassroomId(), true);
  });

  $discipline.on('change', async function () {
    if (suppressRecordedAtOnDisciplineChange) {
      return;
    }
    $recorded_at.val(null).trigger('change');
  });


  async function getStep(classroom_id) {
    return $.ajax({
      url: Routes.fetch_step_school_term_recovery_diary_records_pt_br_path({
        classroom_id: classroom_id,
        format: 'json'
      }),
      success: handleFetchStepByClassroomSuccess,
      error: handleFetchStepByClassroomError
    });
  }

  function handleFetchStepByClassroomSuccess(data) {
    var preservedStepId = $step.val();
    let selectedSteps = data.map(function (step) {
      return { id: step['id'], text: step['description'] };
    });

    $step.select2({ data: selectedSteps });

    if (preservedStepId && _.find(selectedSteps, function (s) { return String(s.id) === String(preservedStepId); })) {
      $step.val(preservedStepId).trigger('change');
    } else if (selectedSteps.length === 1) {
      $step.val(selectedSteps[0].id).trigger('change');
    }
  };

  function handleFetchStepByClassroomError() {
    flashMessages.error('Ocorreu um erro ao buscar a etapa da turma.');
  };

  async function getNumberOfDecimalPlaces(classroom_id) {
    return $.ajax({
      url: Routes.fetch_number_of_decimal_places_school_term_recovery_diary_records_pt_br_path({
        classroom_id: classroom_id,
        format: 'json'
      }),
      success: handleFetchNumberOfDecimalByClassroomSuccess,
      error: handleFetchNumberOfDecimalByClassroomError
    });
  }

  function handleFetchNumberOfDecimalByClassroomSuccess() {
  };

  function handleFetchNumberOfDecimalByClassroomError() {
    flashMessages.error('É necessário configurar uma avaliação numérica');
  };

  async function fetchDisciplines(classroom_id) {
    var preservedDisciplineId = getDisciplineId();
    return $.ajax({
      url: Routes.disciplines_pt_br_path({ classroom_id: classroom_id, format: 'json' }),
      success: function (disciplines) {
        handleFetchDisciplinesSuccess(disciplines, preservedDisciplineId);
      },
      error: handleFetchDisciplinesError
    });
  };

  function handleFetchDisciplinesSuccess(disciplines, preservedDisciplineId) {
    var selectedDisciplines = disciplines.map(function (discipline) {
      return { id: discipline['id'], text: discipline['description'] };
    });

    $discipline.select2({ data: selectedDisciplines });

    var chosenId = preservedDisciplineId;
    if (!chosenId || !_.find(selectedDisciplines, function (d) { return String(d.id) === String(chosenId); })) {
      chosenId = selectedDisciplines[0] && selectedDisciplines[0].id;
    }
    if (chosenId) {
      $discipline.val(chosenId).trigger('change');
    }
  };

  function handleFetchDisciplinesError() {
    flashMessages.error('Ocorreu um erro ao buscar as disciplinas da turma selecionada.');
  };


  function fetchExamRule() {
    let classroom_id = getClassroomId();

    if (!_.isEmpty(classroom_id)) {
      $.ajax({
        url: Routes.for_school_term_type_recovery_exam_rules_pt_br_path({ classroom_id: classroom_id, format: 'json' }),
        success: handleFetchExamRuleSuccess,
        error: handleFetchExamRuleError
      });
    }
  }

  function handleFetchExamRuleSuccess(data) {
    if (!$.isEmptyObject(data)) {
      examRule = data.exam_rule;

      if (!$.isEmptyObject(examRule) && examRule.recovery_type === 0) {
        flashMessages.error('A turma selecionada está configurada para não permitir o lançamento de recuperações de etapas.');
      } else {
        flashMessages.pop('');
      }
    }
  }

  function handleFetchExamRuleError() {
    flashMessages.error('Ocorreu um erro ao buscar a regra de avaliação da turma selecionada.');
  }

  $recorded_at.on('focusin', function () {
    $(this).data('oldDate', $(this).val());
  });

  function checkPersistedDailyNote() {
    let step_id = $step.select2('val');
    let classroom_id = getClassroomId();

    let filter = {
      by_classroom_id: getClassroomId(),
      by_unity_id: getUnityId(),
      by_discipline_id: getDisciplineId(),
      by_step_id: step_id,
      with_daily_note_students: true
    };

    if (!_.isEmpty(step_id) && !_.isEmpty(classroom_id)) {
      $.ajax({
        url: Routes.search_daily_notes_pt_br_path({ filter: filter, format: 'json' }),
        success: handleFetchCheckPersistedDailyNoteSuccess,
        error: handleFetchCheckPersistedDailyNoteError
      });
    }
  }

  function handleFetchCheckPersistedDailyNoteSuccess(data) {
    if (_.isEmpty(data.daily_notes)) {
      flashMessages.error('A turma selecionada não possui notas lançadas nesta etapa.');
    } else {
      flashMessages.pop('');
      let step_id = $step.select2('val');
      let recorded_at = $recorded_at.val();
      fetchStudentsInRecovery(getClassroomId(), getDisciplineId(), examRule, step_id, recorded_at, studentInStepRecovery);
    }
  }

  function studentInStepRecovery(data) {
    let students = data.students;

    if (!_.isEmpty(students)) {
      let element_counter = 0;
      let existing_ids = [];
      let fetched_ids = [];

      hideNoItemMessage();

      $('#recovery-diary-record-students').children('tr').each(function () {
        if (!$(this).hasClass('destroy')) {
          existing_ids.push(parseInt(this.id));
        }
      });
      existing_ids.shift();

      if (_.isEmpty(existing_ids)) {
        _.each(students, function (student) {
          let element_id = new Date().getTime() + element_counter++;

          buildStudentField(element_id, student);
        });
        loadDecimalMasks();
      } else {
        $.each(students, function (index, student) {
          let fetched_id = student.id;

          fetched_ids.push(fetched_id);

          if ($.inArray(fetched_id, existing_ids) == -1) {
            if ($('#' + fetched_id).length != 0 && $('#' + fetched_id).hasClass('destroy')) {
              restoreStudent(fetched_id);
            } else {
              let element_id = new Date().getTime() + element_counter++;

              buildStudentField(element_id, student, index);
            }
            existing_ids.push(fetched_id);
          }
        });

        loadDecimalMasks();

        _.each(existing_ids, function (existing_id) {
          if ($.inArray(existing_id, fetched_ids) == -1) {
            removeStudent(existing_id);
          }
        });
      }
    } else {
      $recorded_at.val($recorded_at.data('oldDate'));

      flashMessages.error('Nenhum aluno encontrado.');
    }

    function buildStudentField(element_id, student, index = null) {
      let html = JST['templates/school_term_recovery_diary_records/student_fields']({
        id: student.id,
        name: student.name,
        average: student.average,
        scale: 2,
        element_id: element_id,
        exempted_from_discipline: student.exempted_from_discipline
      });

      let $tbody = $('#recovery-diary-record-students');

      if ($.isNumeric(index)) {
        $(html).insertAfter($tbody.children('tr')[index]);
      } else {
        $tbody.append(html);
      }
    }

    function removeStudent(id) {
      $('#' + id).hide();
      $('#' + id).addClass('destroy');
      $('.nested-fields#' + id + ' [id$=_destroy]').val(true);
    }

    function restoreStudent(id) {
      $('#' + id).show();
      $('#' + id).removeClass('destroy');
      $('.nested-fields#' + id + ' [id$=_destroy]').val(false);
    }
  }

  function handleFetchCheckPersistedDailyNoteError() {
    flashMessages.error('Ocorreu um erro ao buscar as notas lançadas para esta turma nesta etapa.');
  }

  function hideNoItemMessage() {
    $('.no_item_found').hide();
  }

  function showNoItemMessage() {
    if (!$('.nested-fields').is(":visible")) {
      $('.no_item_found').show();
    }
  }

  function loadDecimalMasks() {
    let numberOfDecimalPlaces = $('#recovery-diary-record-students').data('scale') || 1;
    $('.nested-fields input.decimal').inputmask('customDecimal', { digits: numberOfDecimalPlaces });
  }

  $step.on('change', function () {
    checkPersistedDailyNote();
  });

  $recorded_at.on('change', function () {
    checkPersistedDailyNote();
  });

  $submitButton.on('click', function () {
    $recorded_at.unbind();
  });

  async function initializeFixedClassroom() {
    var classroom_id = getClassroomId();
    if (_.isEmpty(classroom_id)) return;

    await loadClassroomDependencies(classroom_id, false);
    fetchExamRule();
  }

  initializeFixedClassroom();
  loadDecimalMasks();
});
