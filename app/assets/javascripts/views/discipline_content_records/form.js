$(function () {
  'use strict';

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
  var $class_number = $('#discipline_content_record_class_number');
  var idContentsCounter = 1;

  $classroom.on('change', function () {
    var classroom_id = $classroom.val();

    $discipline.val(null).trigger('change');
    $discipline.select2({ data: [] });

    if (!_.isEmpty(classroom_id)) {
      reloadDisciplinesForSelectedDate();
    }
    loadContents();
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

  var applyDisciplinesToSelect = function (payload) {
    var disciplines = payload.disciplines || [];
    var selectedDisciplines = _.map(disciplines, function (discipline) {
      return { id: discipline.id, text: discipline.description || discipline.name || discipline.text || '' };
    });
    var previousDiscipline = $discipline.val();

    $discipline.select2({ data: selectedDisciplines });

    if (previousDiscipline && _.find(selectedDisciplines, function (d) { return String(d.id) === String(previousDiscipline); })) {
      $discipline.select2('val', previousDiscipline);
    } else if (selectedDisciplines.length === 1) {
      $discipline.select2('val', selectedDisciplines[0].id);
    } else {
      $discipline.val('').trigger('change');
    }

    toggleRecordDateAlert(payload.message);
    countLessons();
    loadContents();
  };

  var reloadDisciplinesForSelectedDate = function () {
    var classroom_id = $classroom.val();
    var date = $recordDate.val();

    if (_.isEmpty(classroom_id) || _.isEmpty(date) || _.isEmpty(date.match(dateRegex))) {
      toggleRecordDateAlert(null);
      loadContents();
      return;
    }

    $.getJSON(apiPaths.disciplinesForRecordDate, {
      classroom_id: classroom_id,
      record_date: date
    }).done(function (payload) {
      applyDisciplinesToSelect(payload || { disciplines: [], message: null });
    }).fail(function () {
      toggleRecordDateAlert('Não foi possível carregar as disciplinas para a data selecionada. Tente novamente.');
    });
  };


  var handleFetchContentsSuccess = function (data) {
    
    // Remove TODOS os conteúdos não manuais antes de adicionar os novos
    // Isso garante que quando a data muda, os conteúdos antigos sejam removidos
    // IMPORTANTE: Remove novamente aqui para garantir que não há itens residuais
    var itemsBefore = $('#contents-list .list-group-item').length;
    
    $('#contents-list .list-group-item').each(function() {
      $(this).remove();
    });
    
    var itemsAfter = $('#contents-list .list-group-item').length;

    // Adiciona os novos conteúdos retornados pelo servidor
    if (!_.isEmpty(data.contents)) {
      _.each(data.contents, function (content) {
        // Verifica se o conteúdo já existe (incluindo os manuais)
        // Se já existe, não adiciona novamente para evitar duplicatas
        var contentExists = $('input[type=checkbox][data-content_description="' + content.description + '"]').length > 0;
        
        if (!contentExists) {
          var html = JST['templates/discipline_content_records/contents_list_item'](content);
          $('#contents-list').append(html);
        }
      });
      $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);
    }
    // Se data.contents estiver vazio, a lista já foi limpa acima, então não há nada a fazer
  }

  var handleFetchContentsError = function () {
    flashMessages.error('Ocorreu um erro ao buscar os conteúdos de acordo com filtros informados.');
  }

  var fetchContents = function (classroom_id, discipline_id, date) {
    var params = {
      classroom_id: classroom_id,
      discipline_id: discipline_id,
      date: date,
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
    // Remove TODOS os objetivos não manuais antes de adicionar os novos
    // Isso garante que quando a data muda, os objetivos antigos sejam removidos
    // IMPORTANTE: Remove novamente aqui para garantir que não há itens residuais
    $('#objectives-list .list-group-item').remove();

    // Adiciona os novos objetivos retornados pelo servidor
    if (!_.isEmpty(data.objectives)) {
      _.each(data.objectives, function (objective) {
        // Verifica se o objetivo já existe (incluindo os manuais)
        // Se já existe, não adiciona novamente para evitar duplicatas
        var objectiveExists = $('input[type=checkbox][data-objective_description="' + objective.description + '"]').length > 0;
        
        if (!objectiveExists) {
          var html = JST['templates/discipline_content_records/objectives_list_item'](objective);
          $('#objectives-list').append(html);
        }
      });
      $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);
    }
    // Se data.objectives estiver vazio, a lista já foi limpa acima, então não há nada a fazer
  }

  var fetchObjectives = function (classroom_id, discipline_id, date) {
    var params = {
      classroom_id: classroom_id,
      discipline_id: discipline_id,
      date: date,
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
    var classroom_id = $classroom.val();
    var discipline_id = $discipline.val();
    var date = $recordDate.val();
    
    // Remove TODOS os conteúdos e objetivos não manuais ANTES de fazer a requisição
    // Isso garante que quando a data muda, os itens antigos sejam removidos imediatamente
    var contentsBefore = $('#contents-list .list-group-item').length;
    var objectivesBefore = $('#objectives-list .list-group-item').length;
        
    // Remove os elementos do DOM de forma mais agressiva
    $('#contents-list .list-group-item').each(function() {
      $(this).remove();
    });
    $('#objectives-list .list-group-item').each(function() {
      $(this).remove();
    });
    
    // Verifica se realmente foram removidos
    var contentsAfter = $('#contents-list .list-group-item').length;
    var objectivesAfter = $('#objectives-list .list-group-item').length;
    
    if (!_.isEmpty(classroom_id) &&
      !_.isEmpty(discipline_id) &&
      !_.isEmpty(date.match(dateRegex))) {

      // Faz as requisições para buscar novos conteúdos e objetivos baseados na nova data
      // As funções de sucesso também removem itens não manuais como segurança extra
      fetchContents(classroom_id, discipline_id, date);
      fetchObjectives(classroom_id, discipline_id, date);
    } else {
      // Se os campos não estão preenchidos, limpa a lista completamente
      $('#contents-list .list-group-item').remove();
      $('#objectives-list .list-group-item').remove();
    }
  }

  $discipline.on('change', function () {
    loadContents();
    countLessons();
    checkTeacherAbsenceForContent();
  });

  function checkTeacherAbsenceForContent() {
    var classroom_id = $classroom.val();
    var discipline_id = $discipline.val();
    var date = $recordDate.val();
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
    reloadDisciplinesForSelectedDate();
    checkTeacherAbsenceForContent();
  });

  $class_number.on('change', function () {
    checkTeacherAbsenceForContent();
  });

  if (!isModalForm && $classroom.val() && $recordDate.val()) {
    reloadDisciplinesForSelectedDate();
  } else if (!$("#contents-list li").length) {
    loadContents();
  } else if ($discipline.val()) {
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
    var classroom_id = $classroom.val();
    var discipline_id = $discipline.val();
    var date = $recordDate.val();

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
