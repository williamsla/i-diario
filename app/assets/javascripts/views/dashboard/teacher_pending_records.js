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
      '<div class="panel-heading">' +
        '<h4 class="panel-title">' + stepData.step_name + 
        ' <small>(' + stepData.start_at + ' a ' + stepData.end_at + ')</small></h4>' +
      '</div>' +
      '<div class="panel-body">' +
        '<div class="table-responsive">' +
          '<table class="table table-bordered table-only-inner-bordered table-striped table-hover" style="font-size: 14px;">' +
            '<thead>' +
              '<tr>' +
                '<th>Disciplina</th>' +
                '<th style="width: 120px; text-align: center;">Pend. Frequência</th>' +
                '<th style="width: 120px; text-align: center;">Pend. Conteúdo</th>' +
                '<th>Datas Pendentes</th>' +
              '</tr>' +
            '</thead>' +
            '<tbody>';

    // Uma linha para cada disciplina
    _.each(stepData.pending_records, function(record) {
      // Aumentar quantidade de datas exibidas de 5 para 15
      var maxDates = 15;
      var frequencyDates = record.pending_frequency_dates.length > 0 ? 
        record.pending_frequency_dates.slice(0, maxDates).join(', ') + 
        (record.pending_frequency_dates.length > maxDates ? '...' : '') : 
        'Nenhuma';
      
      var contentDates = record.pending_content_dates.length > 0 ? 
        record.pending_content_dates.slice(0, maxDates).join(', ') + 
        (record.pending_content_dates.length > maxDates ? '...' : '') : 
        'Nenhuma';

      var frequencyBadgeClass = record.pending_frequency_count > 0 ? 'badge-danger' : 'badge-success';
      var contentBadgeClass = record.pending_content_count > 0 ? 'badge-danger' : 'badge-success';

      stepHtml += '<tr>' +
        '<td><strong>' + record.discipline + '</strong></td>' +
        '<td style="text-align: center;"><span class="badge ' + frequencyBadgeClass + '">' + record.pending_frequency_count + '</span></td>' +
        '<td style="text-align: center;"><span class="badge ' + contentBadgeClass + '">' + record.pending_content_count + '</span></td>' +
        '<td>' +
          '<strong>Freq:</strong> ' + frequencyDates + '<br>' +
          '<strong>Cont:</strong> ' + contentDates +
        '</td>' +
        '</tr>';
    });

    stepHtml += '</tbody>' +
          '</table>' +
        '</div>' +
      '</div>' +
    '</div>';

    $stepContainer.html(stepHtml);
  }

  function handleFetchTeacherPendingRecordsError() {
    $container.html('<div class="alert alert-danger">Ocorreu um erro ao buscar os dias pendentes.</div>');
    flashMessages.error('Ocorreu um erro ao buscar os dias pendentes.');
  }

  fetchSteps();
});

