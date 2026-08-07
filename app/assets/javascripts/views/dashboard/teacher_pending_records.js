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

    var today = new Date();
    today.setHours(0, 0, 0, 0);

    var currentStep = null;
    _.each(steps, function(step) {
      var startDate = parseStepDate(step.start_at_iso);
      var endDate = parseStepDate(step.end_at_iso);

      if (today >= startDate && today <= endDate) {
        currentStep = step;
        return false;
      }
    });

    var stepsHtml = '<div class="pending-steps-selector form-group">' +
      '<div class="pending-steps-list" role="listbox" aria-label="Etapas"></div>' +
      '<div class="pending-step-detail" aria-live="polite"></div>' +
      '</div>' +
      '<div id="step-data-container"></div>';

    $container.html(stepsHtml);

    var $stepsList = $container.find('.pending-steps-list');

    _.each(steps, function(step) {
      var isCurrent = currentStep && String(currentStep.id) === String(step.id);
      var isFuture = isFutureStep(step, today);
      var fullName = stepFullName(step);
      var compactLabel = stepCompactLabel(step);
      var datesLabel = (step.start_at || '') + ' a ' + (step.end_at || '');
      var badgeHtml = '';

      if (isCurrent) {
        badgeHtml = '<span class="pending-step-btn__badge">Atual</span>';
      } else if (isFuture) {
        badgeHtml = '<span class="pending-step-btn__badge pending-step-btn__badge--future">Não iniciado</span>';
      }

      var $button = $('<button type="button" class="pending-step-btn" role="option" aria-selected="false"></button>')
        .attr('data-step-id', step.id)
        .attr('aria-label', isFuture ? fullName + ' (não iniciado)' : fullName)
        .toggleClass('is-current', isCurrent)
        .toggleClass('is-disabled', isFuture)
        .prop('disabled', isFuture)
        .attr('aria-disabled', isFuture ? 'true' : 'false')
        .attr('title', isFuture ? 'Etapa ainda não iniciada. Disponível a partir de ' + (step.start_at || '') + '.' : null)
        .html(
          '<span class="pending-step-btn__compact">' + _.escape(compactLabel) + '</span>' +
          '<span class="pending-step-btn__desktop">' +
            '<span class="pending-step-btn__header">' +
              '<span class="pending-step-btn__name">' + _.escape(fullName) + '</span>' +
              badgeHtml +
            '</span>' +
            '<span class="pending-step-btn__dates">' + _.escape(datesLabel) + '</span>' +
          '</span>'
        );

      $stepsList.append($button);
    });

    $stepsList.on('click', '.pending-step-btn:not(:disabled)', function() {
      selectStep($(this).data('step-id'));
    });

    var startedSteps = _.filter(steps, function(step) {
      return !isFutureStep(step, today);
    });
    var stepToSelect = currentStep || _.last(startedSteps);

    if (stepToSelect) {
      selectStep(stepToSelect.id);
    } else {
      $('#step-data-container').html(
        '<div class="alert alert-info">Nenhuma etapa iniciada ainda.</div>'
      );
    }
  }

  function parseStepDate(isoDate) {
    var parts = String(isoDate || '').split('-');
    var year = parseInt(parts[0], 10);
    var month = parseInt(parts[1], 10) - 1;
    var day = parseInt(parts[2], 10);
    var date = new Date(year, month, day);
    date.setHours(0, 0, 0, 0);
    return date;
  }

  function isFutureStep(step, today) {
    return parseStepDate(step.start_at_iso) > today;
  }

  function stepFullName(step) {
    var name = step.name || '';
    var withoutDates = name.replace(/\s*\([^)]*\)\s*$/, '').trim();

    if (withoutDates) {
      return withoutDates;
    }

    if (step.step_number) {
      return step.step_number + 'ª etapa';
    }

    return name;
  }

  function stepCompactLabel(step) {
    var fullName = stepFullName(step);
    var match = fullName.match(/^(\d+)\s*[ºª°]?\s*(.+)$/i);

    if (match) {
      var number = match[1];
      var type = match[2].trim();
      var compactType = type
        .replace(/^bimestre$/i, 'Bim')
        .replace(/^trimestre$/i, 'Tri')
        .replace(/^semestre$/i, 'Sem')
        .replace(/^unidade$/i, 'Uni')
        .replace(/^etapa$/i, 'Eta');

      if (compactType !== type || /^(Bi|Tri|Sem|Un|Et)$/i.test(compactType)) {
        return number + 'º ' + compactType;
      }

      return number + 'º ' + type.substring(0, 3);
    }

    if (step.step_number) {
      return step.step_number + 'º';
    }

    return fullName;
  }

  function stepTypeLabel(step) {
    var fullName = stepFullName(step);
    var match = fullName.match(/^\d+\s*[ºª°]?\s*(.+)$/i);

    if (match) {
      return match[1].trim().toLowerCase();
    }

    return 'etapa';
  }

  function selectStep(stepId) {
    var today = new Date();
    today.setHours(0, 0, 0, 0);

    var selectedStep = _.find(steps, function(step) {
      return String(step.id) === String(stepId);
    });

    if (selectedStep && isFutureStep(selectedStep, today)) {
      return;
    }

    var $buttons = $container.find('.pending-step-btn');

    $buttons.each(function() {
      var $btn = $(this);
      var isActive = String($btn.data('step-id')) === String(stepId);
      $btn.toggleClass('is-active', isActive).attr('aria-selected', isActive ? 'true' : 'false');
    });

    if (stepId) {
      fetchStepData(stepId);
    } else {
      $('#step-data-container').html('');
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

  function notInLessonsBoardHtml() {
    return '<span class="not-in-lessons-board-label" style="display: inline-block; color: #8a6d3b; max-width: 180px; line-height: 1.4;" title="Solicite à coordenação que adicione essa disciplina no quadro de aulas da turma.">' +
      '<i class="fa fa-exclamation-triangle" style="margin-right: 5px;"></i>' +
      'Não consta no quadro de aulas' +
    '</span>';
  }

  function renderPendingDatesButton(count, type, recordId, recordIndex, iconClass) {
    if (count > 0) {
      return '<button type="button" class="btn toggle-dates" style="background-color: #ff9800' + (type === 'content' ? '' : ' !important') + '; color: white; border: none; cursor: pointer; border-radius: 20px; padding: 6px 15px;" data-target="#' + type + '-' + recordId + '" data-record-index="' + recordIndex + '">' +
        '<i class="fa ' + iconClass + '" style="margin-right: 5px;"></i>' +
        count + ' datas' +
      '</button>';
    }

    return '<span class="btn" style="border-radius: 20px; padding: 6px 15px; cursor: default; color: green; font-size: 30px;" title="Tudo certo com ' + (type === 'freq' ? 'a frequência nessa disciplina' : 'o conteúdo nessa disciplina') + ' na etapa selecionada.">' +
      '<i class="fa fa-check-circle"' + (type === 'content' ? ' style="margin-right: 5px;"' : '') + '></i>' +
    '</span>';
  }

  function handleFetchStepDataSuccess(stepData) {
    var $stepContainer = $('#step-data-container');
    
    if(!stepData || !stepData.pending_records || stepData.pending_records.length === 0){
      $stepContainer.html('<div class="alert alert-info">Ocorreu um erro ao buscar os dias pendentes-.</div>');
      return;
    }

    var frequencyByDiscipline = stepData.frequency_by_discipline !== false;
    var showAvaliationsColumns = stepData.has_numeric_avaliation === true;
    var totalRows = stepData.pending_records.length;
    var firstRecord = stepData.pending_records[0];
    var avaliationsHeaderHtml = showAvaliationsColumns ?
      '<th style="width: 160px; text-align: center;">Alunos sem Nota</th>' :
      '';

    var stepHtml = '<div class="pending-records-table-wrap">' +
        '<div class="table-responsive">' +
          '<table class="table table-bordered table-only-inner-bordered table-striped table-hover pending-records-table">' +
            '<thead>' +
              '<tr>' +
                '<th>Disciplina</th>' +
                '<th style="width: 200px; text-align: center;">Frequências Pendentes</th>' +
                '<th style="width: 200px; text-align: center;">Conteúdos Pendentes</th>' +
                avaliationsHeaderHtml +
              '</tr>' +
            '</thead>' +
            '<tbody>';

    // Uma linha para cada disciplina
    var recordIndex = 0;
    _.each(stepData.pending_records, function(record) {
      var recordId = 'record-' + stepData.step_id + '-' + recordIndex;
      var mergedFreqId = 'freq-merged-' + stepData.step_id;
      var notInLessonsBoard = record.in_lessons_board === false;

      // Frequências: laranja quando há pendências; verde quando está ok (0 datas)
      var frequencyButton;
      if (frequencyByDiscipline) {
        frequencyButton = notInLessonsBoard ?
          notInLessonsBoardHtml() :
          renderPendingDatesButton(record.pending_frequency_count, 'freq', recordId, recordIndex, 'fa-calendar');
      } else {
        // Frequência única para todas as disciplinas: só na primeira linha
        if (recordIndex === 0) {
          frequencyButton = firstRecord.pending_frequency_count > 0 ?
            '<button type="button" class="btn toggle-dates toggle-dates-merged-freq" style="background-color: #ff9800 !important; border-color: #ff9800 !important; color: white !important; border: none; cursor: pointer; border-radius: 20px; padding: 6px 15px;" data-target="#' + mergedFreqId + '" data-record-index="0">' +
              '<i class="fa fa-calendar" style="margin-right: 5px;"></i>' +
              firstRecord.pending_frequency_count + ' datas' +
            '</button>' :
            '<span class="btn" style="border-radius: 20px; padding: 6px 15px; cursor: default; color: green; font-size: 30px;" title="Tudo certo com a frequência nessa etapa.">' +
              '<i class="fa fa-check-circle"></i>' +
            '</span>';
        }
      }

      var avaliationsColumnsHtml = '';

      if (showAvaliationsColumns) {
        var studentsWithoutNoteCount = record.students_without_note_count || 0;
        var showingClassroomTotal = record.students_without_note_from_classroom_total === true;
        var studentsWithoutNoteBadge;

        if (showingClassroomTotal) {
          studentsWithoutNoteBadge = '<span class="btn" style="border-radius: 20px; padding: 6px 15px; cursor: default; background-color: #ff9800; color: white;" title="Nenhuma avaliação criada na etapa. Total de alunos da turma com nota numérica.">' +
            studentsWithoutNoteCount + ' aluno(s)' +
          '</span>';
        } else if (studentsWithoutNoteCount > 0) {
          studentsWithoutNoteBadge = '<span class="btn" style="border-radius: 20px; padding: 6px 15px; cursor: default; background-color: #ff9800; color: white;" title="Alunos com nota pendente em avaliações numéricas da etapa.">' +
            studentsWithoutNoteCount + ' aluno(s)' +
          '</span>';
        } else {
          studentsWithoutNoteBadge = '<span class="btn" style="border-radius: 20px; padding: 6px 15px; cursor: default; color: green; font-size: 30px;" title="Todas as notas lançadas nas avaliações da etapa.">' +
            '<i class="fa fa-check-circle"></i>' +
          '</span>';
        }

        avaliationsColumnsHtml =
          '<td style="text-align: center;">' + studentsWithoutNoteBadge + '</td>';
      }

      // Conteúdos: laranja quando há pendências; verde quando está ok (0 datas)
      var contentButton = notInLessonsBoard ?
        notInLessonsBoardHtml() :
        renderPendingDatesButton(record.pending_content_count, 'cont', recordId, recordIndex, 'fa-file-text');

      if (frequencyByDiscipline) {
        stepHtml += '<tr>' +
          '<td><strong>' + record.discipline + '</strong></td>' +
          '<td style="text-align: center;">' +
            '<div>' + frequencyButton + '</div>' +
            '<div id="freq-' + recordId + '" class="dates-container" style="display: none; margin-top: 10px; padding: 10px; background-color: #f5f5f5; border-radius: 4px; text-align: left;">' +
              '<div class="loading-dates"><i class="fa fa-spinner fa-spin"></i> Carregando datas...</div>' +
            '</div>' +
          '</td>' +
          '<td style="text-align: center;">' +
            '<div>' + contentButton + '</div>' +
            '<div id="cont-' + recordId + '" class="dates-container" style="display: none; margin-top: 10px; padding: 10px; background-color: #f5f5f5; border-radius: 4px; text-align: left;">' +
              '<div class="loading-dates"><i class="fa fa-spinner fa-spin"></i> Carregando datas...</div>' +
            '</div>' +
          '</td>' +
          avaliationsColumnsHtml +
          '</tr>';
      } else {
        // Frequência não por disciplina: coluna de frequência só na primeira linha (rowspan)
        if (recordIndex === 0) {
          stepHtml += '<tr>' +
            '<td><strong>' + record.discipline + '</strong></td>' +
            '<td rowspan="' + totalRows + '" style="text-align: center; vertical-align: middle;">' +
              '<div>' + frequencyButton + '</div>' +
              '<div id="' + mergedFreqId + '" class="dates-container" style="display: none; margin-top: 10px; padding: 10px; background-color: #f5f5f5; border-radius: 4px; text-align: left;">' +
                '<div class="loading-dates"><i class="fa fa-spinner fa-spin"></i> Carregando datas...</div>' +
              '</div>' +
            '</td>' +
            '<td style="text-align: center;">' +
              '<div>' + contentButton + '</div>' +
              '<div id="cont-' + recordId + '" class="dates-container" style="display: none; margin-top: 10px; padding: 10px; background-color: #f5f5f5; border-radius: 4px; text-align: left;">' +
                '<div class="loading-dates"><i class="fa fa-spinner fa-spin"></i> Carregando datas...</div>' +
              '</div>' +
            '</td>' +
            avaliationsColumnsHtml +
            '</tr>';
        } else {
          stepHtml += '<tr>' +
            '<td><strong>' + record.discipline + '</strong></td>' +
            '<td style="text-align: center;">' +
              '<div>' + contentButton + '</div>' +
              '<div id="cont-' + recordId + '" class="dates-container" style="display: none; margin-top: 10px; padding: 10px; background-color: #f5f5f5; border-radius: 4px; text-align: left;">' +
                '<div class="loading-dates"><i class="fa fa-spinner fa-spin"></i> Carregando datas...</div>' +
              '</div>' +
            '</td>' +
            avaliationsColumnsHtml +
            '</tr>';
        }
      }

      recordIndex++;
    });

    stepHtml += '</tbody>' +
          '</table>' +
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
      
      // Se o container não tem dados carregados, usar datas já na resposta ou buscar via AJAX
      if($target.find('.loading-dates').length > 0 || $target.text().trim() === '' || $target.text().indexOf('Carregando') !== -1) {
        var recordIndex = $(this).data('record-index');
        if (recordIndex === undefined) {
          var recordId = targetId.replace('#freq-', '').replace('#cont-', '');
          var parts = recordId.split('-');
          recordIndex = recordId.indexOf('merged') !== -1 ? 0 : parseInt(parts[parts.length - 1], 10);
        }
        var record = stepData.pending_records[recordIndex];
        var isFrequency = targetId.indexOf('freq-') !== -1;
        var label = isFrequency ? 'Datas pendentes de frequência' : 'Datas pendentes de conteúdo';

        // Datas já vieram na resposta inicial: exibir na hora (sem nova requisição)
        var datesFromRecord = isFrequency ? record.pending_frequency_dates : record.pending_content_dates;
        if (datesFromRecord !== undefined && Array.isArray(datesFromRecord)) {
          $target.html(
            '<strong>' + label + ':</strong><br>' +
            (datesFromRecord.length > 0 ? datesFromRecord.join(', ') : 'Nenhuma')
          ).slideDown();
          return;
        }

        // Fallback: buscar datas via AJAX (respostas antigas ou dados não incluídos)
        $target.html('<div class="loading-dates"><i class="fa fa-spinner fa-spin"></i> Carregando datas...</div>').slideDown();
        var idParam = record.knowledge_area_id ?
          { knowledge_area_id: record.knowledge_area_id } :
          { discipline_id: record.discipline_id };
        $.ajax({
          url: Routes.dates_dashboard_teacher_pending_records_pt_br_path(
            Object.assign({
              format: 'json',
              step_id: stepData.step_id
            }, idParam)
          ),
          success: function(data) {
            var dates = isFrequency ? data.pending_frequency_dates : data.pending_content_dates;
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

