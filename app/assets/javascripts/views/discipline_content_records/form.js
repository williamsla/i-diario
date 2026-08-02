$(function () {
  'use strict';

  $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);

  // Regular expression for dd/mm/yyyy date including validation for leap year and more
  var dateRegex = '^(?:(?:31(\\/)(?:0?[13578]|1[02]))\\1|(?:(?:29|30)(\\/)(?:0?[1,3-9]|1[0-2])\\2))(?:(?:1[6-9]|[2-9]\\d)?\\d{2})$|^(?:29(\\/)0?2\\3(?:(?:(?:1[6-9]|[2-9]\\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00))))$|^(?:0?[1-9]|1\\d|2[0-8])(\\/)(?:(?:0?[1-9])|(?:1[0-2]))\\4(?:(?:1[6-9]|[2-9]\\d)?\\d{2})$';
  var flashMessages = new FlashMessages();
  var $form = $('#discipline-content-record-form');
  var isModalForm = $form.data('modal') === true || $form.data('modal') === 'true';
  var apiPaths = {
    disciplinesForRecordDate: $form.data('disciplinesForRecordDateUrl')
  };
  var $recordDateEmptyAlert = $('#record-date-empty-alert');
  var $recordDateEmptyMessage = $('#record-date-empty-message');
  var $recordDateHint = $('#record-date-hint');
  var $classroom = $('#discipline_content_record_content_record_attributes_classroom_id');
  var $discipline = $('#discipline_content_record_discipline_id');
  var $recordDate = $('#discipline_content_record_content_record_attributes_record_date');
  var $student = $('#discipline_content_record_content_record_attributes_student_id');
  var $class_number = $('#discipline_content_record_class_number');
  var idContentsCounter = 1;
  var isDisciplineReadonly = $discipline.prop('readonly');
  // Registro novo: limpa a lista inteira ao trocar data/disciplina.
  // Edição: preserva .manual (salvos/usuário) e só substitui itens vindos do plano via AJAX.
  var isPersistedRecord = !!$('#discipline_content_record_content_record_attributes_id').val();

  var clearContentsAndObjectivesLists = function () {
    if (isPersistedRecord) {
      $('#contents-list .list-group-item:not(.manual)').remove();
      $('#objectives-list .list-group-item:not(.manual)').remove();
    } else {
      $('#contents-list .list-group-item').remove();
      $('#objectives-list .list-group-item').remove();
    }
  };

  var getInputValue = function ($input) {
    if (!$input || !$input.length) {
      return '';
    }

    try {
      if ($input.data('select2')) {
        return $input.select2('val');
      }
    } catch (e) {}

    return $input.val();
  };

  $classroom.on('change', function () {
    var classroom_id = getInputValue($classroom);

    $discipline.select2('val', '');
    $discipline.select2({ data: [] });

    if (!_.isEmpty(classroom_id)) {
      reloadDisciplinesForSelectedDate({ reloadContents: true });
    }
  });

  var syncSubmitButtonState = function () {
    if (isModalForm) {
      return;
    }

    if (!$recordDateEmptyAlert.hasClass('hidden')) {
      $form.find('input[type=submit]').addClass('disabled');
      return;
    }

    $form.find('input[type=submit]').removeClass('disabled');
  };

  var toggleRecordDateAlert = function (message) {
    if (isModalForm) {
      return;
    }

    if (message) {
      $recordDateEmptyMessage.text(message);
      $recordDateEmptyAlert.removeClass('hidden');
      $recordDateHint.text(message).removeClass('hidden');
    } else {
      $recordDateEmptyAlert.addClass('hidden');
      $recordDateEmptyMessage.text('');
      $recordDateHint.text('').addClass('hidden');
    }

    syncSubmitButtonState();
  };

  var applyDisciplinesToSelect = function (payload, options) {
    options = options || {};
    var disciplines = payload.disciplines || [];
    var selectedDisciplines = _.map(disciplines, function (discipline) {
      var label = discipline.description || discipline.name || discipline.text || '';
      return { id: discipline.id, text: label, name: label };
    });
    var previousDiscipline = getInputValue($discipline);

    if (isDisciplineReadonly && previousDiscipline) {
      var disciplineInList = _.find(selectedDisciplines, function (d) {
        return String(d.id) === String(previousDiscipline);
      });

      if (!disciplineInList) {
        var currentData = $discipline.select2('data');
        var currentLabel = currentData && (currentData.text || currentData.name);

        if (currentLabel) {
          selectedDisciplines.push({
            id: previousDiscipline,
            text: currentLabel,
            name: currentLabel
          });
        }
      }
    }

    $discipline.select2({ data: selectedDisciplines });

    if (previousDiscipline && _.find(selectedDisciplines, function (d) { return String(d.id) === String(previousDiscipline); })) {
      $discipline.select2('val', previousDiscipline);
    } else if (!isDisciplineReadonly && selectedDisciplines.length === 1) {
      $discipline.select2('val', selectedDisciplines[0].id);
    } else if (!isDisciplineReadonly) {
      $discipline.select2('val', '');
      $discipline.trigger('change');
    }

    toggleRecordDateAlert(payload.message);
    countLessons();

    if (options.reloadContents) {
      loadContents();
    } else {
      loadContentsIfNeeded();
    }
  };

  var reloadDisciplinesForSelectedDate = function (options) {
    options = options || {};
    var classroom_id = getInputValue($classroom);
    var date = getInputValue($recordDate);

    if (_.isEmpty(classroom_id) || _.isEmpty(date) || _.isEmpty(date.match(dateRegex))) {
      toggleRecordDateAlert(null);
      return;
    }

    $.getJSON(apiPaths.disciplinesForRecordDate, {
      classroom_id: classroom_id,
      record_date: date
    }).done(function (payload) {
      applyDisciplinesToSelect(payload || { disciplines: [], message: null }, options);
    }).fail(function () {
      toggleRecordDateAlert('Não foi possível carregar as disciplinas para a data selecionada. Tente novamente.');
    });
  };


  var handleFetchContentsSuccess = function (data) {
    if (isPersistedRecord) {
      $('#contents-list .list-group-item:not(.manual)').remove();
    }

    // Adiciona os novos conteúdos retornados pelo servidor
    if (!_.isEmpty(data.contents)) {
      _.each(data.contents, function (content) {
        // Verifica se o conteúdo já existe (incluindo os manuais)
        // Se já existe, não adiciona novamente para evitar duplicatas
        var contentExists = $('#contents-list input[type=checkbox][data-content_description="' + content.description + '"]').length > 0;
        
        if (!contentExists) {
          var html = JST['templates/discipline_content_records/contents_list_item'](content);
          $('#contents-list').append(html);
        }
      });
      $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);
    }
  }

  var handleFetchContentsError = function () {
    flashMessages.error('Ocorreu um erro ao buscar os conteúdos de acordo com filtros informados.');
  }

  var fetchContents = function (classroom_id, discipline_id, date) {
    var params = {
      classroom_id: classroom_id,
      discipline_id: discipline_id,
      date: date,
      student_id: getInputValue($student),
      fetch_for_discipline_records: true,
      format: "json"
    }
    $.ajax({
      url: Routes.contents_pt_br_path(params),
      success: handleFetchContentsSuccess,
      error: handleFetchContentsError
    });

  }

  var handleFetchObjectivesSuccess = function (data) {
    if (isPersistedRecord) {
      $('#objectives-list .list-group-item:not(.manual)').remove();
    }

    // Adiciona os novos objetivos retornados pelo servidor
    if (!_.isEmpty(data.objectives)) {
      _.each(data.objectives, function (objective) {
        // Verifica se o objetivo já existe (incluindo os manuais)
        // Se já existe, não adiciona novamente para evitar duplicatas
        var objectiveExists = $('#objectives-list input[type=checkbox][data-objective_description="' + objective.description + '"]').length > 0;
        
        if (!objectiveExists) {
          var html = JST['templates/discipline_content_records/objectives_list_item'](objective);
          $('#objectives-list').append(html);
        }
      });
      $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);
    }
  }

  var fetchObjectives = function (classroom_id, discipline_id, date) {
    var params = {
      classroom_id: classroom_id,
      discipline_id: discipline_id,
      date: date,
      student_id: getInputValue($student),
      fetch_for_discipline_records: true,
      format: "json"
    }
    $.ajax({
      url: Routes.objectives_pt_br_path(params),
      success: handleFetchObjectivesSuccess,
      error: handleFetchContentsError
    });

  }

  var loadContents = function () {
    var classroom_id = getInputValue($classroom);
    var discipline_id = getInputValue($discipline);
    var date = getInputValue($recordDate);

    if (!_.isEmpty(classroom_id) &&
      !_.isEmpty(discipline_id) &&
      !_.isEmpty(date) &&
      !_.isEmpty(date.match(dateRegex))) {

      clearContentsAndObjectivesLists();
      fetchContents(classroom_id, discipline_id, date);
      fetchObjectives(classroom_id, discipline_id, date);
    }
    // Se filtros inválidos: não limpar a lista (evita apagar HTML renderizado na edição).
  };

  // Só busca conteúdos via AJAX quando as listas ainda estão vazias (ex.: novo registro).
  // Na edição, o servidor já envia conteúdos/habilidades; chamar loadContents apagaria tudo.
  var loadContentsIfNeeded = function () {
    var hasContents = $('#contents-list .list-group-item').length > 0;
    var hasObjectives = $('#objectives-list .list-group-item').length > 0;
    if (hasContents || hasObjectives) {
      return;
    }
    loadContents();
  };

  $discipline.on('change', function () {
    loadContents();
    countLessons();
    checkTeacherAbsenceForContent();
  });

  $student.on('change', function () {
    loadContents();
  });

  function checkTeacherAbsenceForContent() {
    var classroom_id = getInputValue($classroom);
    var discipline_id = getInputValue($discipline);
    var date = getInputValue($recordDate);
    var class_number = $class_number.val();

    if (_.isEmpty(classroom_id) || _.isEmpty(date) || !date.match(dateRegex)) {
      $('#teacher_absence_blocks_content_alert').hide();
      return;
    }

    $.ajax({
      url: Routes.check_teacher_absence_discipline_content_records_pt_br_path({
        record_date: date,
        classroom_id: classroom_id,
        discipline_id: discipline_id || '',
        class_number: class_number || '',
        format: 'json'
      }),
      success: function (data) {
        if (data && data.blocked) {
          $('#teacher_absence_blocks_content_alert').show();
        } else {
          $('#teacher_absence_blocks_content_alert').hide();
        }
      },
      error: function () {
        $('#teacher_absence_blocks_content_alert').hide();
      }
    });
  }

  $recordDate.on('change changeDate valid-date', function () {
    reloadDisciplinesForSelectedDate({ reloadContents: true });
    checkTeacherAbsenceForContent();
  });

  $class_number.on('change', function () {
    checkTeacherAbsenceForContent();
  });

  if (!isModalForm && getInputValue($classroom) && getInputValue($recordDate)) {
    reloadDisciplinesForSelectedDate();
  } else if (!$("#contents-list li").length) {
    loadContentsIfNeeded();
  } else if (getInputValue($discipline)) {
    countLessons();
  }

  checkTeacherAbsenceForContent();

  function fetchDisciplines(classroom_id) {
    reloadDisciplinesForSelectedDate();
  }

  function setClassNumberValue(value) {
    var normalizedValue = value && parseInt(value, 10) > 0 ? String(value) : '';

    try {
      if ($class_number.data('select2')) {
        $class_number.select2('val', normalizedValue);
      }
    } catch (e) {}

    $class_number.val(normalizedValue).trigger('change');
  }

  function countLessons() {
    var classroom_id = getInputValue($classroom);
    var discipline_id = getInputValue($discipline);
    var date = getInputValue($recordDate);

    if (_.isEmpty(classroom_id) || _.isEmpty(discipline_id) || _.isEmpty(date) || !date.match(dateRegex)) {
      setClassNumberValue('');
      return;
    }

    $.ajax({
      url: Routes.count_lessons_lessons_boards_pt_br_path({
        classroom_id: classroom_id,
        discipline_id: discipline_id,
        date: date,
        format: 'json'
      }),
      success: handleCountLessonsSuccess,
      error: handleCountLessonsError
    });
  }

  function handleCountLessonsSuccess(data) {
    setClassNumberValue(data);
  }

  function handleCountLessonsError() {
    flashMessages.error('Ocorreu um erro ao contar aulas da disciplina na data selecionada.');
  }

  $('#discipline_content_record_content_record_attributes_contents_tags').on('change', function (e) {
    if (e.val.length) {
      var uniqueId = 'customId_' + idContentsCounter++;
      var content_description = e.val.join(", ");
      if (content_description.trim().length &&
        !$('input[type=checkbox][data-content_description="' + content_description + '"]').length) {

        var html = JST['templates/layouts/contents_list_manual_item']({
          id: uniqueId,
          description: content_description,
          model_name: 'discipline_content_record',
          submodel_name: 'content_record'
        });
        $('#contents-list').append(html);
        $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);
      } else {
        var content_input = $('input[type=checkbox][data-content_description="' + content_description + '"]');
        content_input.closest('li').show();
        content_input.prop('checked', true).trigger('change');
      }

      $('.discipline_content_record_content_record_contents_tags .select2-input').val("");
    }
    $(this).val(null).trigger('change');
  });

  $('#discipline_content_record_content_record_attributes_objectives_tags').on('change', function (e) {
    if (e.val.length) {
      var uniqueId = 'customId_' + idContentsCounter++;
      var objective_description = e.val.join(", ");
      if (objective_description.trim().length &&
        !$('input[type=checkbox][data-objective_description="' + objective_description + '"]').length) {

        var html = JST['templates/layouts/objectives_list_manual_item']({
          id: uniqueId,
          description: objective_description,
          model_name: 'discipline_content_record',
          submodel_name: 'content_record'
        });

        $('#objectives-list').append(html);
        $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);
      } else {
        var objective_input = $('input[type=checkbox][data-objective_description="' + objective_description + '"]');
        objective_input.closest('li').show();
        objective_input.prop('checked', true).trigger('change');
      }

      $('.discipline_content_record_content_record_objectives_tags .select2-input').val("");
    }
    $(this).val(null).trigger('change');
  });

  // Previne envio do form ao pressionar Enter no campo de tags (Select2)
  $(document).on('keypress', function(e) {
    const isEnter = (e.which === 13 || e.key === 'Enter');

    if (isEnter) {
      const $target = $(e.target);

      // Verifica se está no campo Select2 de contents_tags
      if ($target.closest('.discipline_content_record_content_record_contents_tags').length) {
        e.preventDefault();  // Cancela o submit do form

        // Encontra o <select> real do select2 e limpa
        // TODO: NÃO ESTÀ FUNCIONANDO, NÂO LIMPA OS CONTEUDOS NOVOS
        const $select = $target.closest('.discipline_content_record_content_record_contents_tags').find('select');
        $select.val(null).trigger('change');

        return false;        // Segurança extra
      }
    }
  });


});
