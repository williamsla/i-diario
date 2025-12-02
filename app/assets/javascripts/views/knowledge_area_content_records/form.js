$(function () {
  'use strict';

  // Initialize all checkboxes (for edit mode and new mode)
  $('.list-group.checked-list-box .list-group-item:not(.initialized)').each(initializeListEvents);

  // Regular expression for dd/mm/yyyy date including validation for leap year and more
  var dateRegex = '^(?:(?:31(\\/)(?:0?[13578]|1[02]))\\1|(?:(?:29|30)(\\/)(?:0?[1,3-9]|1[0-2])\\2))(?:(?:1[6-9]|[2-9]\\d)?\\d{2})$|^(?:29(\\/)0?2\\3(?:(?:(?:1[6-9]|[2-9]\\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00))))$|^(?:0?[1-9]|1\\d|2[0-8])(\\/)(?:(?:0?[1-9])|(?:1[0-2]))\\4(?:(?:1[6-9]|[2-9]\\d)?\\d{2})$';
  var flashMessages = new FlashMessages();
  var $classroom = $('#knowledge_area_content_record_content_record_attributes_classroom_id');
  var $knowledgeArea = $('#knowledge_area_content_record_knowledge_area_ids');
  var $recordDate = $('#knowledge_area_content_record_content_record_attributes_record_date');
  var $contents = $('#knowledge_area_content_record_content_record_attributes_contents_tags');
  var $objectives = $('#knowledge_area_content_record_content_record_attributes_objectives_tags');
  var idContentsCounter = 1;
  var idObjectivesCounter = 1;

  $classroom.on('change', function(){
    var classroom_id = $classroom.select2('val');

    $knowledgeArea.select2('val', '');
    $knowledgeArea.select2({ data: [] });

    if (!_.isEmpty(classroom_id)) {
      fetchKnowledgeAreas(classroom_id);
    }
    loadContents();
  });


  var handleFetchContentsSuccess = function(data){
    
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
    
      _.each(data.contents, function(content) {
        // Verifica se o conteúdo já existe (incluindo os manuais)
        // Se já existe, não adiciona novamente para evitar duplicatas
        var contentExists = $('input[type=checkbox][data-content_description="'+content.description+'"]').length > 0;
        
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
    
    // Remove TODOS os objetivos não manuais antes de adicionar os novos
    // Isso garante que quando a data muda, os objetivos antigos sejam removidos
    // IMPORTANTE: Remove novamente aqui para garantir que não há itens residuais
    $('#objectives-list .list-group-item').remove();

    // Adiciona os novos objetivos retornados pelo servidor
    if (!_.isEmpty(data.objectives)) {
      _.each(data.objectives, function(objective) {
        // Verifica se o objetivo já existe (incluindo os manuais)
        // Se já existe, não adiciona novamente para evitar duplicatas
        var objectiveExists = $('input[type=checkbox][data-objective_description="'+objective.description+'"]').length > 0;
        
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
    
    // Se knowledge_area_ids é um array, converte para string separada por vírgula
    if (_.isArray(knowledge_area_ids)) {
      knowledge_area_ids = knowledge_area_ids.join(',');
    }

    if (!_.isEmpty(classroom_id) &&
        !_.isEmpty(knowledge_area_ids) &&
        !_.isEmpty(date) &&
        !_.isEmpty(date.match(dateRegex))) {
      // Se knowledge_area_ids é string, converte para array
      var knowledge_area_ids_array = _.isArray(knowledge_area_ids) ? knowledge_area_ids : knowledge_area_ids.split(',').filter(function(id) { return id.trim() !== ''; });

      // Faz as requisições para buscar novos conteúdos e objetivos baseados na nova data
      // As funções de sucesso também removem itens não manuais como segurança extra
      fetchContents(classroom_id, knowledge_area_ids_array, date);
      fetchObjectives(classroom_id, knowledge_area_ids_array, date);
    } else {
      // Se os campos não estão preenchidos, limpa a lista completamente
      $('#contents-list .list-group-item').remove();
      $('#objectives-list .list-group-item').remove();
    }
  }

  $knowledgeArea.on('change', function(){
    loadContents();
  });
  
  // Também escuta o evento select2:select para garantir que funciona
  $knowledgeArea.on('select2:select select2:unselect', function(){
    setTimeout(function() {
      loadContents();
    }, 100);
  });

  // Sempre recarrega conteúdos e objetivos quando a data mudar
  $recordDate.on('change', function(){
    loadContents();
  });

  // Carregar conteúdos e objetivos automaticamente quando a página é carregada
  // Aguarda um pouco para garantir que o select2 está inicializado
  setTimeout(function() {
    // Lê o classroom_id (pode ser hidden ou select2)
    var classroom_id = null;
    if ($classroom.length && $classroom.is('select')) {
      classroom_id = $classroom.select2('val') || $classroom.val();
    } else {
      classroom_id = $classroom.val();
    }
        
    // Se há classroom_id, carrega as knowledge areas primeiro
    if (!_.isEmpty(classroom_id)) {
      // Verifica se as knowledge areas já foram carregadas
      var knowledgeAreaData = [];
      if ($knowledgeArea.length && $knowledgeArea.is('select')) {
        knowledgeAreaData = $knowledgeArea.select2('data') || [];
      }
      
      if (_.isEmpty(knowledgeAreaData) || knowledgeAreaData.length === 0) {
        fetchKnowledgeAreas(classroom_id);
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
    $.ajax({
      url: Routes.knowledge_areas_pt_br_path({ classroom_id: classroom_id, format: 'json' }),
      success: handlefetchKnowledgeAreasSuccess,
      error: handlefetchKnowledgeAreasError
    });
  };

  function handlefetchKnowledgeAreasSuccess(knowledge_areas) {
    
    // Filtra áreas de conhecimento válidas (com id e description não vazios)
    var validKnowledgeAreas = _.filter(knowledge_areas, function(knowledge_area) {
      return knowledge_area && knowledge_area['id'] && knowledge_area['description'] && 
             knowledge_area['id'] !== '' && knowledge_area['description'] !== '';
    });
        
    var selectedKnowledgeAreas = _.map(validKnowledgeAreas, function(knowledge_area) {
      return { id: knowledge_area['id'], text: knowledge_area['description'] };
    });

    // Verifica se o elemento existe
    if ($knowledgeArea.length) {
      var isSelect = $knowledgeArea.is('select');
      var isInput = $knowledgeArea.is('input');
      
      // Verifica se o select2 já está inicializado
      var isSelect2Initialized = $knowledgeArea.data('select2') !== undefined;
      
      // Filtra áreas válidas removendo qualquer item com id "empty" ou vazio
      var validSelectedKnowledgeAreas = _.filter(selectedKnowledgeAreas, function(item) {
        return item && item.id && item.id !== '' && item.id !== 'empty' && item.id !== 'null';
      });
            
      if (isSelect || isInput) {
        if (isSelect2Initialized) {
          // Se já está inicializado, apenas atualiza os dados
          $knowledgeArea.select2({ data: validSelectedKnowledgeAreas });
        } else {
          // Se não está inicializado, inicializa com os dados
          $knowledgeArea.select2({ data: validSelectedKnowledgeAreas });
        }
        
        // Aguarda um pouco para garantir que o select2 foi atualizado
        setTimeout(function() {
          // Se há knowledge_area_ids já definidos (ex: via parâmetro na URL), seleciona-os
          var hiddenKnowledgeArea = $('input[name="knowledge_area_content_record[knowledge_area_ids]"]');
          if (hiddenKnowledgeArea.length && hiddenKnowledgeArea.val()) {
            var ids = hiddenKnowledgeArea.val().split(',').filter(function(id) { return id && id !== '' && id !== 'empty'; });

            if (ids.length > 0) {
              // Define o valor diretamente no elemento e depois atualiza o select2
              $knowledgeArea.val(ids);
              $knowledgeArea.select2('val', ids);
              $knowledgeArea.trigger('change');
              // Carrega os conteúdos após selecionar as áreas de conhecimento
              setTimeout(function() {
                loadContents();
              }, 200);
            }
          } else if (validSelectedKnowledgeAreas.length > 0) {
            // Sempre seleciona a primeira área de conhecimento válida (não vazia)
            var firstKnowledgeArea = validSelectedKnowledgeAreas[0];
            var firstKnowledgeAreaId = firstKnowledgeArea.id;
                        
            // Verifica o valor atual
            var currentVal = $knowledgeArea.select2('val') || [];
                        
            // Primeiro define o valor no elemento HTML
            $knowledgeArea.val([firstKnowledgeAreaId]);
            
            // Depois atualiza o select2
            $knowledgeArea.select2('val', [firstKnowledgeAreaId]);
            
            // Verifica se foi selecionado
            var newVal = $knowledgeArea.select2('val');
            
            // Se ainda não foi selecionado, tenta novamente com método alternativo
            if (_.isEmpty(newVal) || (_.isArray(newVal) && newVal.length === 0) || 
                (_.isArray(newVal) && !newVal.includes(firstKnowledgeAreaId.toString()) && !newVal.includes(firstKnowledgeAreaId))) {
            
              // Tenta usar o método de seleção do select2 diretamente
              var select2Instance = $knowledgeArea.data('select2');
              if (select2Instance) {
                select2Instance.val([firstKnowledgeAreaId]).trigger('change');
                newVal = $knowledgeArea.select2('val');
              }
            }
            
            // Dispara o evento change
            $knowledgeArea.trigger('change');
            
            // Carrega os conteúdos após selecionar
            setTimeout(function() {
              loadContents();
            }, 500);
          } 
        }, 400);
      }
    }
  };

  function handlefetchKnowledgeAreasError() {
    flashMessages.error('Ocorreu um erro ao buscar as áreas de conhecimento da turma selecionada.');
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
