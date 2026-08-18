$(function () {
  'use strict';

  // Initialize all checkboxes (for edit mode and new mode)
  $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);

  // Regular expression for dd/mm/yyyy date including validation for leap year and more
  var dateRegex = '^(?:(?:31(\\/)(?:0?[13578]|1[02]))\\1|(?:(?:29|30)(\\/)(?:0?[1,3-9]|1[0-2])\\2))(?:(?:1[6-9]|[2-9]\\d)?\\d{2})$|^(?:29(\\/)0?2\\3(?:(?:(?:1[6-9]|[2-9]\\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00))))$|^(?:0?[1-9]|1\\d|2[0-8])(\\/)(?:(?:0?[1-9])|(?:1[0-2]))\\4(?:(?:1[6-9]|[2-9]\\d)?\\d{2})$';
  var isoDateRegex = /^\d{4}-\d{2}-\d{2}$/;
  var flashMessages = new FlashMessages();
  var $form = $('#knowledge-area-content-record-form');
  var isModalForm = $form.data('modal') === true || $form.data('modal') === 'true' || $form.attr('data-modal') === 'true';
  var apiPaths = {
    knowledgeAreasForRecordDate: $form.attr('data-knowledge-areas-for-record-date-url') || $form.data('knowledgeAreasForRecordDateUrl'),
    findExisting: $form.attr('data-find-existing-url') || $form.data('findExistingUrl'),
    newUrl: $form.attr('data-new-url') || $form.data('newUrl'),
    editUrlTemplate: $form.attr('data-edit-url-template') || $form.data('editUrlTemplate')
  };
  var $recordDateEmptyAlert = $('#record-date-empty-alert');
  var $recordDateEmptyMessage = $('#record-date-empty-message');
  var $recordDateHint = $('#record-date-hint');
  var $classroom = $('#knowledge_area_content_record_content_record_attributes_classroom_id');
  var $knowledgeArea = $('#knowledge_area_content_record_knowledge_area_ids');
  var $recordDate = $('#knowledge_area_content_record_content_record_attributes_record_date');
  var $student = $('#knowledge_area_content_record_content_record_attributes_student_id');
  var $contents = $('#knowledge_area_content_record_content_record_attributes_contents_tags');
  var $objectives = $('#knowledge_area_content_record_content_record_attributes_objectives_tags');
  var idContentsCounter = 1;
  var idObjectivesCounter = 1;
  var isPersistedRecord = !!$('#knowledge_area_content_record_content_record_attributes_id').val();
  var currentRecordId = $form.attr('data-record-id') || $form.data('recordId') || null;
  var lastStudentId = String($student.val() || '');
  var redirectingToExisting = false;

  var isValidRecordDate = function (date) {
    return !_.isEmpty(date) && (!_.isEmpty(date.match(dateRegex)) || isoDateRegex.test(date));
  };

  var appendModalParam = function (url) {
    if (!isModalForm || _.isEmpty(url)) {
      return url;
    }

    return url + (url.indexOf('?') >= 0 ? '&' : '?') + 'modal=true';
  };

  var readClassroomId = function () {
    if ($classroom.length && $classroom.is('select')) {
      return $classroom.select2('val') || $classroom.val();
    }
    return $classroom.val();
  };

  var readKnowledgeAreaIds = function () {
    var knowledge_area_ids = null;
    if ($knowledgeArea.length && $knowledgeArea.is('select')) {
      knowledge_area_ids = $knowledgeArea.select2('val') || $knowledgeArea.val();
    } else {
      knowledge_area_ids = $knowledgeArea.val();
    }

    if (_.isEmpty(knowledge_area_ids)) {
      var hiddenKnowledgeArea = $('input[name="knowledge_area_content_record[knowledge_area_ids]"]');
      if (hiddenKnowledgeArea.length && hiddenKnowledgeArea.val()) {
        knowledge_area_ids = hiddenKnowledgeArea.val();
      }
    }

    if (_.isArray(knowledge_area_ids)) {
      knowledge_area_ids = knowledge_area_ids.join(',');
    }

    return knowledge_area_ids;
  };

  var readPeriod = function () {
    var match = window.location.search.match(/[?&]period=([^&]*)/);
    return match ? decodeURIComponent(match[1]) : '';
  };

  var redirectToEdit = function (recordId) {
    if (!recordId || String(recordId) === String(currentRecordId)) {
      loadContents();
      return;
    }

    var editUrl = apiPaths.editUrlTemplate
      ? String(apiPaths.editUrlTemplate).replace('__ID__', recordId)
      : '/registros-de-conteudos-por-areas-de-conhecimento/' + recordId + '/editar';

    redirectingToExisting = true;
    window.location.href = appendModalParam(editUrl);
  };

  var redirectToNew = function (studentId) {
    var classroom_id = readClassroomId();
    var knowledge_area_ids = readKnowledgeAreaIds();
    var date = $recordDate.val();
    var params = [];

    if (!_.isEmpty(classroom_id)) {
      params.push('classroom_id=' + encodeURIComponent(classroom_id));
    }
    if (!_.isEmpty(date)) {
      params.push('recorded_at=' + encodeURIComponent(date));
    }
    if (!_.isEmpty(studentId)) {
      params.push('student_id=' + encodeURIComponent(studentId));
    }
    if (!_.isEmpty(knowledge_area_ids)) {
      var firstAreaId = String(knowledge_area_ids).split(',')[0];
      if (firstAreaId) {
        params.push('knowledge_area_id=' + encodeURIComponent(firstAreaId));
      }
    }
    var period = readPeriod();
    if (!_.isEmpty(period)) {
      params.push('period=' + encodeURIComponent(period));
    }
    if (isModalForm) {
      params.push('modal=true');
    }

    var newUrl = apiPaths.newUrl || '/registros-de-conteudos-por-areas-de-conhecimento/novo';
    redirectingToExisting = true;
    window.location.href = newUrl + (params.length ? '?' + params.join('&') : '');
  };

  var loadExistingRecordForStudent = function (studentId) {
    if (redirectingToExisting || _.isEmpty(apiPaths.findExisting)) {
      loadContents();
      return;
    }

    var classroom_id = readClassroomId();
    var knowledge_area_ids = readKnowledgeAreaIds();
    var date = $recordDate.val();
    studentId = studentId == null ? ($student.val() || '') : studentId;

    if (_.isEmpty(classroom_id) || _.isEmpty(knowledge_area_ids) || !isValidRecordDate(date)) {
      loadContents();
      return;
    }

    $.ajax({
      url: apiPaths.findExisting,
      dataType: 'json',
      data: {
        classroom_id: classroom_id,
        knowledge_area_ids: knowledge_area_ids,
        record_date: date,
        student_id: studentId,
        period: readPeriod()
      }
    }).done(function (payload) {
      var existingId = payload && payload.id;

      if (existingId) {
        redirectToEdit(existingId);
        return;
      }

      // Em edição: aluno/geral sem registro próprio → abre novo para não sobrescrever o atual
      if (isPersistedRecord) {
        redirectToNew(studentId);
        return;
      }

      loadContents();
    }).fail(function () {
      loadContents();
    });
  };

  var clearContentsAndObjectivesLists = function () {
    if (isPersistedRecord) {
      $('#contents-list .list-group-item:not(.manual)').remove();
      $('#objectives-list .list-group-item:not(.manual)').remove();
    } else {
      $('#contents-list .list-group-item').remove();
      $('#objectives-list .list-group-item').remove();
    }
  };

  $classroom.on('change', function(){
    var classroom_id = $classroom.select2('val');

    $knowledgeArea.select2('val', '');
    $knowledgeArea.select2({ data: [] });

    if (!_.isEmpty(classroom_id)) {
      reloadKnowledgeAreasForSelectedDate();
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

  var applyKnowledgeAreasToSelect = function (payload) {
    var knowledgeAreas = payload.knowledge_areas || [];
    var selectedKnowledgeAreas = _.map(knowledgeAreas, function (knowledgeArea) {
      return {
        id: knowledgeArea.id,
        text: knowledgeArea.description || knowledgeArea.name || knowledgeArea.text || ''
      };
    }).filter(function (item) {
      return item.id && item.id !== 'empty';
    });

    if (!$knowledgeArea.length) {
      toggleRecordDateAlert(payload.message);
      return;
    }

    var previousValues = $knowledgeArea.select2('val') || [];

    $knowledgeArea.select2({ data: selectedKnowledgeAreas });

    var hiddenKnowledgeArea = $('input[name="knowledge_area_content_record[knowledge_area_ids]"]').not($knowledgeArea);
    var hiddenIds = [];
    if (hiddenKnowledgeArea.length && hiddenKnowledgeArea.val()) {
      hiddenIds = hiddenKnowledgeArea.val().split(',').filter(function (id) {
        return id && id !== '' && id !== 'empty';
      });
    }

    var preservedValues = _.filter(previousValues, function (id) {
      return _.find(selectedKnowledgeAreas, function (item) { return String(item.id) === String(id); });
    });

    var hiddenValues = _.filter(hiddenIds, function (id) {
      return _.find(selectedKnowledgeAreas, function (item) { return String(item.id) === String(id); });
    });

    if (!_.isEmpty(hiddenValues)) {
      $knowledgeArea.select2('val', hiddenValues);
    } else if (!_.isEmpty(preservedValues)) {
      $knowledgeArea.select2('val', preservedValues);
    } else if (selectedKnowledgeAreas.length === 1) {
      $knowledgeArea.select2('val', [selectedKnowledgeAreas[0].id]);
    } else {
      $knowledgeArea.select2('val', []);
    }

    toggleKnowledgeAreaFieldVisibility(selectedKnowledgeAreas.length);

    $knowledgeArea.trigger('change');
    toggleRecordDateAlert(payload.message);

    if (!payload.message) {
      setTimeout(function () {
        loadContentsAfterKnowledgeAreasIfNeeded();
      }, 200);
    }
  };

  var countAvailableKnowledgeAreas = function (elements) {
    return _.filter(elements || [], function (item) {
      return item && item.id && item.id !== 'empty';
    }).length;
  };

  var toggleKnowledgeAreaFieldVisibility = function (areasCount) {
    var $wrapper = $('#knowledge-area-field-wrapper');
    if (!$wrapper.length) {
      $wrapper = $knowledgeArea.closest('.col');
    }
    if (!$wrapper.length) return;

    if (areasCount === 1) {
      $wrapper.hide();
    } else if (areasCount > 1) {
      $wrapper.show();
    } else {
      $wrapper.hide();
    }
  };

  var reloadKnowledgeAreasForSelectedDate = function () {
    var classroom_id = null;
    if ($classroom.length && $classroom.is('select')) {
      classroom_id = $classroom.select2('val') || $classroom.val();
    } else {
      classroom_id = $classroom.val();
    }

    var date = $recordDate.val();

    if (_.isEmpty(classroom_id) || _.isEmpty(date) || _.isEmpty(date.match(dateRegex))) {
      toggleRecordDateAlert(null);
      return;
    }

    $.getJSON(apiPaths.knowledgeAreasForRecordDate, {
      classroom_id: classroom_id,
      record_date: date
    }).done(function (payload) {
      applyKnowledgeAreasToSelect(payload || { knowledge_areas: [], message: null });
    }).fail(function () {
      toggleRecordDateAlert('Não foi possível carregar as áreas de conhecimento para a data selecionada. Tente novamente.');
    });
  };


  var handleFetchContentsSuccess = function(data){
    if (isPersistedRecord) {
      $('#contents-list .list-group-item:not(.manual)').remove();
    }
    
    // Adiciona os novos conteúdos retornados pelo servidor
    if (!_.isEmpty(data.contents)) {
    
      _.each(data.contents, function(content) {
        // Verifica se o conteúdo já existe (incluindo os manuais)
        // Se já existe, não adiciona novamente para evitar duplicatas
        var contentExists = $('#contents-list input[type=checkbox][data-content_description="'+content.description+'"]').length > 0;
        
        if (!contentExists) {
          var html = JST['templates/knowledge_area_content_records/contents_list_item'](content);
          $('#contents-list').append(html);
        }
      });
      // Initialize all checkboxes, including those that are already checked
      $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);
    }
  }

  var handleFetchContentsError = function(){
    flashMessages.error('Ocorreu um erro ao buscar os conteúdos de acordo com filtros informados.');
  }

  var fetchContents = function(classroom_id, knowledge_area_ids, date){
    var params = {
      classroom_id: classroom_id,
      knowledge_area_ids: knowledge_area_ids,
      date: date,
      student_id: $student.val(),
      fetch_for_knowledge_area_records: true,
      format: "json"
    }
        
    $.ajax({
      url: Routes.contents_pt_br_path(params),
      success: handleFetchContentsSuccess,
      error: function(xhr, status, error) {
        console.error('Error fetching contents:', error, xhr.responseText);
        handleFetchContentsError();
      }
    });

  }

  var handleFetchObjectivesSuccess = function(data){
    if (isPersistedRecord) {
      $('#objectives-list .list-group-item:not(.manual)').remove();
    }

    // Adiciona os novos objetivos retornados pelo servidor
    if (!_.isEmpty(data.objectives)) {
      _.each(data.objectives, function(objective) {
        // Verifica se o objetivo já existe (incluindo os manuais)
        // Se já existe, não adiciona novamente para evitar duplicatas
        var objectiveExists = $('#objectives-list input[type=checkbox][data-objective_description="'+objective.description+'"]').length > 0;
        
        if (!objectiveExists) {
          var html = JST['templates/knowledge_area_content_records/objectives_list_item'](objective);
          $('#objectives-list').append(html);
        }
      });
      $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);
    }
  }

  var fetchObjectives = function(classroom_id, knowledge_area_ids, date){
    var params = {
      classroom_id: classroom_id,
      knowledge_area_ids: knowledge_area_ids,
      date: date,
      student_id: $student.val(),
      fetch_for_knowledge_area_records: true,
      format: "json"
    }
        
    $.ajax({
      url: Routes.objectives_pt_br_path(params),
      success: handleFetchObjectivesSuccess,
      error: function(xhr, status, error) {
        console.error('Error fetching objectives:', error, xhr.responseText);
        handleFetchContentsError();
      }
    });

  }

  var loadContents = function(){
    // Tenta ler o valor do select2, se não conseguir, lê do campo hidden ou do valor direto
    var classroom_id = null;
    if ($classroom.length && $classroom.is('select')) {
      classroom_id = $classroom.select2('val') || $classroom.val();
    } else {
      classroom_id = $classroom.val();
    }
    
    var knowledge_area_ids = null;
    if ($knowledgeArea.length && $knowledgeArea.is('select')) {
      knowledge_area_ids = $knowledgeArea.select2('val') || $knowledgeArea.val();
    } else {
      knowledge_area_ids = $knowledgeArea.val();
    }
    
    var date = $recordDate.val();  
    
    // Se knowledge_area_ids está vazio, tenta ler do campo hidden (para modais)
    if (_.isEmpty(knowledge_area_ids)) {
      var hiddenKnowledgeArea = $('input[name="knowledge_area_content_record[knowledge_area_ids]"]');
      if (hiddenKnowledgeArea.length && hiddenKnowledgeArea.val()) {
        knowledge_area_ids = hiddenKnowledgeArea.val();
      }
    }

    // Se knowledge_area_ids é um array, converte para string separada por vírgula
    if (_.isArray(knowledge_area_ids)) {
      knowledge_area_ids = knowledge_area_ids.join(',');
    }

    if (!_.isEmpty(classroom_id) &&
        !_.isEmpty(knowledge_area_ids) &&
        isValidRecordDate(date)) {
      clearContentsAndObjectivesLists();

      var knowledge_area_ids_array = _.isArray(knowledge_area_ids) ? knowledge_area_ids : knowledge_area_ids.split(',').filter(function(id) { return id.trim() !== ''; });

      fetchContents(classroom_id, knowledge_area_ids_array, date);
      fetchObjectives(classroom_id, knowledge_area_ids_array, date);
    }
    // Se filtros inválidos: não limpar a lista (evita apagar HTML renderizado na edição).
  }

  // Só busca conteúdos via AJAX quando as listas ainda estão vazias (ex.: novo registro).
  // Na edição, o servidor já envia conteúdos/habilidades; chamar loadContents apagaria tudo.
  var loadContentsAfterKnowledgeAreasIfNeeded = function() {
    var hasContents = $('#contents-list .list-group-item').length > 0;
    var hasObjectives = $('#objectives-list .list-group-item').length > 0;
    if (hasContents || hasObjectives) {
      return;
    }
    loadContents();
  };

  $knowledgeArea.on('change', function(){
    loadContents();
  });

  var handleStudentSelectionChange = function () {
    var studentId = String($student.val() || '');

    // Ignora change espúrio na inicialização do select2
    if (studentId === lastStudentId) {
      loadContents();
      return;
    }

    lastStudentId = studentId;
    loadExistingRecordForStudent(studentId);
  };

  $student.on('change', handleStudentSelectionChange);
  $student.on('select2:select select2:clear select2:unselect', function () {
    setTimeout(handleStudentSelectionChange, 0);
  });
  
  // Também escuta o evento select2:select para garantir que funciona
  $knowledgeArea.on('select2:select select2:unselect', function(){
    setTimeout(function() {
      loadContents();
    }, 100);
  });

  // Sempre recarrega conteúdos e objetivos quando a data mudar
  $recordDate.on('change', function(){
    reloadKnowledgeAreasForSelectedDate();
    loadContents();
  });

  // Carregar conteúdos e objetivos automaticamente quando a página é carregada
  // Aguarda um pouco para garantir que o select2 está inicializado
  setTimeout(function() {
    // No modal (AEE/NEE) o helper da frequência sempre abre "novo"; busca o registro
    // já salvo na abertura — não só ao trocar o aluno.
    if (!isPersistedRecord && !_.isEmpty(apiPaths.findExisting) && (isModalForm || $student.length)) {
      loadExistingRecordForStudent($student.val() || '');
      return;
    }

    // Lê o classroom_id (pode ser hidden ou select2)
    var classroom_id = null;
    if ($classroom.length && $classroom.is('select')) {
      classroom_id = $classroom.select2('val') || $classroom.val();
    } else {
      classroom_id = $classroom.val();
    }
        
    // Se há classroom_id, carrega as knowledge areas primeiro
    if (!_.isEmpty(classroom_id)) {
      var knowledgeAreaElements = ($knowledgeArea.length && $knowledgeArea.data('elements')) || [];
      var availableAreasCount = countAvailableKnowledgeAreas(knowledgeAreaElements);

      if (availableAreasCount === 0) {
        reloadKnowledgeAreasForSelectedDate();
      } else {
        if (availableAreasCount === 1) {
          var singleArea = _.find(knowledgeAreaElements, function (item) {
            return item && item.id && item.id !== 'empty';
          });
          if (singleArea) {
            $knowledgeArea.select2('val', [singleArea.id]);
          }
        }
        toggleKnowledgeAreaFieldVisibility(availableAreasCount);
      }
    }
    
    // Aguarda um pouco mais e tenta carregar os conteúdos
    setTimeout(function() {
      // Verifica se há knowledge_area_ids já definidos (ex: via parâmetro na URL ou campo hidden)
      var hiddenKnowledgeArea = $('input[name="knowledge_area_content_record[knowledge_area_ids]"]');
      var hasKnowledgeAreaIds = false;
      
      if (hiddenKnowledgeArea.length && hiddenKnowledgeArea.val()) {
        hasKnowledgeAreaIds = true;
        // Seleciona as knowledge areas no select2 se ainda não estiverem selecionadas
        var ids = hiddenKnowledgeArea.val().split(',');
        if ($knowledgeArea.length && $knowledgeArea.is('select')) {
          var currentVal = $knowledgeArea.select2('val') || [];
          if (_.isEmpty(currentVal) || !_.isEqual(currentVal.sort(), ids.sort())) {
            $knowledgeArea.select2('val', ids);
          }
        }
      } else {
        var knowledge_area_ids = null;
        if ($knowledgeArea.length && $knowledgeArea.is('select')) {
          knowledge_area_ids = $knowledgeArea.select2('val') || $knowledgeArea.val();
        } else {
          knowledge_area_ids = $knowledgeArea.val();
        }
        hasKnowledgeAreaIds = !_.isEmpty(knowledge_area_ids);
      }
            
      // Se não há conteúdos na lista E há todos os dados necessários, carrega
      if (!$("#contents-list li").length && hasKnowledgeAreaIds) {
        loadContents();
      }
    }, 500);
  }, 500);

  function fetchKnowledgeAreas(classroom_id) {
    reloadKnowledgeAreasForSelectedDate();
  };

  $contents.on('change', function(e){
    if(e.val.length){
      var uniqueId = 'customId_' + idContentsCounter++;
      var content_description = e.val.join(", ");
      if(content_description.trim().length &&
          !$('input[type=checkbox][data-content_description="'+content_description+'"]').length){

        var html = JST['templates/layouts/contents_list_manual_item']({
          id: uniqueId,
          description: content_description,
          model_name: 'knowledge_area_content_record',
          submodel_name: 'content_record'
        });

        $('#contents-list').append(html);
        $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);
      }else{
        var content_input = $('input[type=checkbox][data-content_description="'+content_description+'"]');
        content_input.closest('li').show();
        content_input.prop('checked', true).trigger('change');
      }

      $('.knowledge_area_content_record_content_record_contents_tags .select2-input').val("");
    }
    $(this).select2('val', '');
  });

  $objectives.on('change', function(e){
    if(e.val.length){
      var uniqueId = 'customId_' + idObjectivesCounter++;
      var objective_description = e.val.join(", ");
      if(objective_description.trim().length &&
          !$('input[type=checkbox][data-objective_description="'+objective_description+'"]').length){

        var html = JST['templates/layouts/objectives_list_manual_item']({
          id: uniqueId,
          description: objective_description,
          model_name: 'knowledge_area_content_record',
          submodel_name: 'content_record'
        });

        $('#objectives-list').append(html);
        $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);
      }else{
        var objective_input = $('input[type=checkbox][data-objective_description="'+objective_description+'"]');
        objective_input.closest('li').show();
        objective_input.prop('checked', true).trigger('change');
      }

      $('.knowledge_area_content_record_content_record_objectives_tags .select2-input').val("");
    }
    $(this).select2('val', '');
  });
});
