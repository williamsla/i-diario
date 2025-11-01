$(function () {
  'use strict';

  // Regular expression for dd/mm/yyyy date including validation for leap year and more
  var dateRegex = '^(?:(?:31(\\/)(?:0?[13578]|1[02]))\\1|(?:(?:29|30)(\\/)(?:0?[1,3-9]|1[0-2])\\2))(?:(?:1[6-9]|[2-9]\\d)?\\d{2})$|^(?:29(\\/)0?2\\3(?:(?:(?:1[6-9]|[2-9]\\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00))))$|^(?:0?[1-9]|1\\d|2[0-8])(\\/)(?:(?:0?[1-9])|(?:1[0-2]))\\4(?:(?:1[6-9]|[2-9]\\d)?\\d{2})$';
  var flashMessages = new FlashMessages();
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
      fetchDisciplines(classroom_id);
    }
    loadContents();
  });


  var handleFetchContentsSuccess = function (data) {
    // Limpar o campo
    $('#contents-list').empty();

    if (!_.isEmpty(data.contents)) {
      _.each(data.contents, function (content) {
        if (!$('input[type=checkbox][data-content_description="' + content.description + '"]').length) {
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
    // Limpar o campo
    $('#objectives-list').empty();

    if (!_.isEmpty(data.objectives)) {
      _.each(data.objectives, function (objective) {
        if (!$('input[type=checkbox][data-objective_description="' + objective.description + '"]').length) {
          var html = JST['templates/discipline_content_records/contents_list_item'](objective);
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
    $('#contents-list .list-group-item:not(.manual)').remove();
    $('#objectives-list .list-group-item:not(.manual)').remove();

    if (!_.isEmpty(classroom_id) &&
      !_.isEmpty(discipline_id) &&
      !_.isEmpty(date.match(dateRegex))) {
      fetchContents(classroom_id, discipline_id, date);
      fetchObjectives(classroom_id, discipline_id, date);
    }
  }

  $discipline.on('change', function () {
    loadContents();
  });

  $recordDate.on('change', function () {
    loadContents();
    countLessons();
  });
  if (!$("#contents-list li").length) {
    loadContents();
  }

  function fetchDisciplines(classroom_id) {
    $.ajax({
      url: Routes.disciplines_pt_br_path({ classroom_id: classroom_id, format: 'json' }),
      success: handleFetchDisciplinesSuccess,
      error: handleFetchDisciplinesError
    });
  };

  function handleFetchDisciplinesSuccess(disciplines) {
    var selectedDisciplines = _.map(disciplines, function (discipline) {
      return { id: discipline['id'], text: discipline['description'] };
    });

    $discipline.select2({ data: selectedDisciplines });
  };

  function handleFetchDisciplinesError() {
    flashMessages.error('Ocorreu um erro ao buscar as disciplinas da turma selecionada.');
  };

  function countLessons() {
    var classroom_id = $classroom.val();
    var discipline_id = $discipline.val();
    var date = $recordDate.val();
    
    if (!_.isEmpty(classroom_id) && !_.isEmpty(discipline_id)) {
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
  }

  function handleCountLessonsSuccess(data) {
    if (data) {
      $class_number.val(data).trigger('change');
    } else {
      $class_number.val('').trigger('change');
    }
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
