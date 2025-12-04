$(function(){
  "use strict";

  var flashMessages = new FlashMessages();
  var $container = $('#teacher-pending-records-container');
  var steps = [];

  function fetchSteps() {
    $.ajax({
      beforeSend: function () {
        $container.html('<div class="text-center"><i class="fa fa-spinner fa-spin"></i> Carregando...</div>');
      },
      url: Routes.dashboard_teacher_pending_records_pt_br_path({
        format: 'json'
      }),
      success: handleFetchStepsSuccess,
      error: handleFetchTeacherPendingRecordsError
    });
  }

  function handleFetchStepsSuccess(data) {
    steps = data.steps || [];
    var hasLessonsBoard = data.has_lessons_board !== false; // Default true se não vier no JSON
    
    // Verificar se a turma tem quadro de aulas
    if(!hasLessonsBoard) {
      $container.html('<div class="alert alert-warning" style="margin-top: 20px;">' +
        '<i class="fa fa-exclamation-triangle"></i> ' +
        'Solicite à coordenação que cadastre o quadro de aulas da turma. Após isso você conseguirá visualizar as datas pendentes de frequência e conteúdo.' +
        '</div>');
      return;
    }
    
    if(steps.length === 0){
      $container.html('<div class="alert alert-info">Nenhuma etapa encontrada.</div>');
      return;
    }

    // Criar select de etapas
    var selectHtml = '<div class="form-group">' +
      '<label for="step-select">Selecione a etapa:</label>' +
      '<select id="step-select" class="form-control" style="max-width: 400px;">' +
      '<option value="">Selecione uma etapa...</option>';
    
    _.each(steps, function(step) {
      selectHtml += '<option value="' + step.id + '">' + step.name + 
        ' (' + step.start_at + ' a ' + step.end_at + ')</option>';
    });
    
    selectHtml += '</select>' +
      '</div>' +
      '<div id="step-data-container"></div>';

    $container.html(selectHtml);

    // Event listener para mudança de etapa
    $('#step-select').on('change', function() {
      var stepId = $(this).val();
      if(stepId) {
        fetchStepData(stepId);
      } else {
        $('#step-data-container').html('');
      }
    });

    // Selecionar etapa da data atual automaticamente
    if(steps.length > 0) {
      var today = new Date();
      today.setHours(0, 0, 0, 0); // Zerar horas para comparação apenas de data
      
      var currentStep = null;
      _.each(steps, function(step) {
        var startDate = new Date(step.start_at_iso);
        var endDate = new Date(step.end_at_iso);
        startDate.setHours(0, 0, 0, 0);
        endDate.setHours(0, 0, 0, 0);
        
        // Verificar se a data atual está dentro do período da etapa
        if(today >= startDate && today <= endDate) {
          currentStep = step;
          return false; // break do loop
        }
      });
      
      // Se não encontrou etapa atual, usar a primeira etapa
      var stepToSelect = currentStep || steps[0];
      $('#step-select').val(stepToSelect.id).trigger('change');
    }
  }

  function fetchStepData(stepId) {
    var $stepContainer = $('#step-data-container');
    
    $.ajax({
      beforeSend: function () {
        $stepContainer.html('<div class="text-center"><i class="fa fa-spinner fa-spin"></i> Carregando...</div>');
      },
      url: Routes.dashboard_teacher_pending_records_pt_br_path({
        format: 'json',
        step_id: stepId
      }),
      success: function(data) {
        handleFetchStepDataSuccess(data.step_data);
      },
      error: handleFetchTeacherPendingRecordsError
    });
  }

  function handleFetchStepDataSuccess(stepData) {
    var $stepContainer = $('#step-data-container');
    
    if(!stepData || !stepData.pending_records || stepData.pending_records.length === 0){
      $stepContainer.html('<div class="alert alert-info">Nenhum registro pendente para esta etapa.</div>');
      return;
    }

    var stepHtml = '<div class="panel panel-default" style="margin-top: 20px;">' +
      '<div class="panel-body">' +
        '<div class="table-responsive">' +
          '<table class="table table-bordered table-only-inner-bordered table-striped table-hover" style="font-size: 14px;">' +
            '<thead>' +
              '<tr>' +
                '<th>Disciplina</th>' +
                '<th style="width: 200px; text-align: center;">Frequências Pendentes</th>' +
                '<th style="width: 200px; text-align: center;">Conteúdos Pendentes</th>' +
              '</tr>' +
            '</thead>' +
            '<tbody>';

    // Uma linha para cada disciplina
    var recordIndex = 0;
    _.each(stepData.pending_records, function(record) {
      var recordId = 'record-' + stepData.step_id + '-' + recordIndex;
      
      // Botão azul para frequências (com ícone de calendário)
      var frequencyButton = record.pending_frequency_count > 0 ? 
        '<button type="button" class="btn btn-primary toggle-dates" style="cursor: pointer; border-radius: 20px; padding: 6px 15px;" data-target="#freq-' + recordId + '">' +
          '<i class="fa fa-calendar" style="margin-right: 5px;"></i>' +
          record.pending_frequency_count + ' datas' +
        '</button>' :
        '<button type="button" class="btn btn-default" style="border-radius: 20px; padding: 6px 15px;" disabled>' +
          '<i class="fa fa-calendar" style="margin-right: 5px;"></i>' +
          '0 datas' +
        '</button>';
      
      // Botão laranja para conteúdos (com ícone de documento/lista)
      var contentButton = record.pending_content_count > 0 ? 
        '<button type="button" class="btn toggle-dates" style="background-color: #ff9800; color: white; border: none; cursor: pointer; border-radius: 20px; padding: 6px 15px;" data-target="#cont-' + recordId + '">' +
          '<i class="fa fa-file-text" style="margin-right: 5px;"></i>' +
          record.pending_content_count + ' datas' +
        '</button>' :
        '<button type="button" class="btn btn-default" style="border-radius: 20px; padding: 6px 15px;" disabled>' +
          '<i class="fa fa-file-text" style="margin-right: 5px;"></i>' +
          '0 datas' +
        '</button>';

      stepHtml += '<tr>' +
        '<td><strong>' + record.discipline + '</strong></td>' +
        '<td style="text-align: center;">' +
          '<div>' +
            frequencyButton +
          '</div>' +
          '<div id="freq-' + recordId + '" class="dates-container" style="display: none; margin-top: 10px; padding: 10px; background-color: #f5f5f5; border-radius: 4px; text-align: left;">' +
            '<div class="loading-dates"><i class="fa fa-spinner fa-spin"></i> Carregando datas...</div>' +
          '</div>' +
        '</td>' +
        '<td style="text-align: center;">' +
          '<div>' +
            contentButton +
          '</div>' +
          '<div id="cont-' + recordId + '" class="dates-container" style="display: none; margin-top: 10px; padding: 10px; background-color: #f5f5f5; border-radius: 4px; text-align: left;">' +
            '<div class="loading-dates"><i class="fa fa-spinner fa-spin"></i> Carregando datas...</div>' +
          '</div>' +
        '</td>' +
        '</tr>';
      
      recordIndex++;
    });

    stepHtml += '</tbody>' +
          '</table>' +
        '</div>' +
      '</div>' +
    '</div>';

    $stepContainer.html(stepHtml);
    
    // Adicionar event listeners para os ícones de lupa
    $stepContainer.find('.toggle-dates').on('click', function(e) {
      e.preventDefault();
      e.stopPropagation();
      var targetId = $(this).data('target');
      var $target = $(targetId);
      
      // Se já está visível, apenas fecha
      if($target.is(':visible')) {
        $target.slideUp();
        return;
      }
      
      // Fechar todos os outros containers de datas
      $stepContainer.find('.dates-container').not($target).slideUp();
      
      // Se o container não tem dados carregados, buscar via AJAX
      if($target.find('.loading-dates').length > 0 || $target.text().trim() === '' || $target.text().indexOf('Carregando') !== -1) {
        var recordId = targetId.replace('#freq-', '').replace('#cont-', '');
        var parts = recordId.split('-');
        var recordIndex = parseInt(parts[parts.length - 1]); // Último elemento é o índice
        var record = stepData.pending_records[recordIndex];
        var isFrequency = targetId.indexOf('freq-') !== -1;
        
        // Mostrar loading
        $target.html('<div class="loading-dates"><i class="fa fa-spinner fa-spin"></i> Carregando datas...</div>').slideDown();
        
        // Buscar datas via AJAX
        $.ajax({
          url: Routes.dates_dashboard_teacher_pending_records_pt_br_path({
            format: 'json',
            step_id: stepData.step_id,
            discipline_id: record.discipline_id
          }),
          success: function(data) {
            var dates = isFrequency ? data.pending_frequency_dates : data.pending_content_dates;
            var label = isFrequency ? 'Datas pendentes de frequência' : 'Datas pendentes de conteúdo';
            
            $target.html(
              '<strong>' + label + ':</strong><br>' +
              (dates.length > 0 ? dates.join(', ') : 'Nenhuma')
            );
          },
          error: function() {
            $target.html('<div class="alert alert-danger">Erro ao carregar datas.</div>');
          }
        });
      } else {
        // Toggle do container atual (já tem dados)
        $target.slideToggle();
      }
    });
  }

  function handleFetchTeacherPendingRecordsError() {
    $container.html('<div class="alert alert-danger">Ocorreu um erro ao buscar os dias pendentes.</div>');
    flashMessages.error('Ocorreu um erro ao buscar os dias pendentes.');
  }

  fetchSteps();
});

