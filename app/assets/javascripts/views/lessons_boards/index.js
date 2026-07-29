$(function () {
  'use strict';

  $('#search_by_unity').on('change', async function () {
    clearClassroomsAndGrades();
    await updateGrades();
    await updateClassrooms();
  })

  $('#search_by_grade').on('change', async function () {
    await updateClassrooms();
  })

  async function updateGrades() {
    let unity_id = $('#search_by_unity').select2('val');
    if (!_.isEmpty(unity_id)) {
      $.ajax({
        url: Routes.grades_by_unity_lessons_boards_pt_br_path({
          unity_id: unity_id,
          format: 'json'
        }),
        success: handleFetchGradesSuccess,
        error: handleFetchGradesError
      });
    }
  }

  function handleFetchGradesSuccess(data) {
    let grades = _.map(data.lessons_boards, function(lessons_board) {
      return { id: lessons_board.table.id, name: lessons_board.table.name, text: lessons_board.table.text };
    });

    $('#search_by_grade').select2({ data: grades })
  }

  function handleFetchGradesError() {
    flashMessages.error('Ocorreu um erro ao buscar as séries.');
  }

  async function updateClassrooms() {
    let unity_id = $('#search_by_unity').select2('val');
    let grade_id = $('#search_by_grade').select2('val');

    if (!_.isEmpty(grade_id) || !_.isEmpty(unity_id)) {
      $.ajax({
        url: Routes.classrooms_filter_lessons_boards_pt_br_path({
          unity_id: unity_id,
          grade_id: grade_id,
          format: 'json'
        }),
        success: handleFetchClassroomsSuccess,
        error: handleFetchClassroomsError
      });
    }
  }

  function handleFetchClassroomsSuccess(data) {
    let classrooms = _.map(data.lessons_boards, function(lessons_board) {
      return { id: lessons_board.table.id, name: lessons_board.table.name, text: lessons_board.table.text };
    });
    $('#search_by_classroom').select2({ data: classrooms })
  }

  function handleFetchClassroomsError() {
    flashMessages.error('Ocorreu um erro ao buscar as turmas.');
  }

  function clearClassroomsAndGrades() {
    $('#search_by_grade').select2('val', '');
    $('#search_by_classroom').select2('val', '');
  }

  function authenticityToken() {
    return $('meta[name="csrf-token"]').attr('content');
  }

  function submitForm(action, method, fields) {
    var form = $('<form>', { method: 'POST', action: action });
    form.append($('<input>', { type: 'hidden', name: '_method', value: method }));
    form.append($('<input>', {
      type: 'hidden',
      name: 'authenticity_token',
      value: authenticityToken()
    }));

    _.each(fields || {}, function (value, name) {
      form.append($('<input>', { type: 'hidden', name: name, value: value }));
    });

    form.appendTo('body').submit();
  }

  function showPurgeDialog(url) {
    if (!url) {
      return;
    }

    bootbox.dialog({
      title: 'Excluir quadro do calendário',
      message:
        '<p>Este quadro deixará de valer para <strong>qualquer dia do calendário letivo</strong> ' +
        'e <strong>não poderá ser recuperado</strong> pela listagem.</p>' +  
        '<div class="checkbox" style="margin-top: 15px;">' +
          '<label>' +
            '<input type="checkbox" id="lessons-board-purge-confirm"> ' +
            'Entendo que o histórico será perdido' +
          '</label>' +
        '</div>',
      buttons: {
        cancel: {
          label: 'Cancelar',
          className: 'btn-default'
        },
        confirm: {
          label: 'Excluir do calendário',
          className: 'btn-danger',
          callback: function () {
            if (!$('#lessons-board-purge-confirm').is(':checked')) {
              flashMessages.error('Confirme que entende que o histórico será perdido.');
              return false;
            }

            submitForm(url, 'delete', { confirm_permanent_delete: '1' });
          }
        }
      }
    });
  }

  $(document).on('click', '.archive-lessons-board', function (e) {
    e.preventDefault();

    var url = $(this).data('url');
    var purgeUrl = $(this).data('purge-url');
    if (!url) {
      return;
    }

    var today = new Date().toISOString().slice(0, 10);

    bootbox.dialog({
      title: 'Arquivar quadro de aula',
      message:
        '<p><strong>Até que dia esse quadro de aulas funcionou?</strong></p>' +
        '<input type="date" class="form-control" id="lessons-board-archive-date" value="' + today + '">' +
        '<div class="well well-sm" style="margin-top: 18px; margin-bottom: 0;">' +
          '<p style="margin-bottom: 8px;">Se este quadro <strong>não for válido em nenhum dia</strong> do calendário letivo:</p>' +
          '<button type="button" class="btn btn-danger btn-sm" id="lessons-board-archive-exclude" ' +
            'data-purge-url="' + (purgeUrl || '') + '">' +
            '<i class="fa fa-trash"></i> Excluir do calendário' +
          '</button>' +
        '</div>',
      buttons: {
        cancel: {
          label: 'Cancelar',
          className: 'btn-default'
        },
        confirm: {
          label: 'Arquivar',
          className: 'btn-primary',
          callback: function () {
            var archivedUntil = $('#lessons-board-archive-date').val();
            if (!archivedUntil) {
              flashMessages.error('Informe até que dia esse quadro de aulas funcionou.');
              return false;
            }

            submitForm(url, 'delete', { archived_until: archivedUntil });
          }
        }
      }
    });
  });

  $(document).on('click', '#lessons-board-archive-exclude', function (event) {
    event.preventDefault();
    var purgeUrl = $(this).data('purge-url');
    bootbox.hideAll();
    showPurgeDialog(purgeUrl);
  });

  $(document).on('click', '.edit-archive-date-lessons-board', function (e) {
    e.preventDefault();

    var url = $(this).data('url');
    var currentDate = $(this).data('current-date') || new Date().toISOString().slice(0, 10);
    if (!url) {
      return;
    }

    bootbox.dialog({
      title: 'Alterar data de arquivamento',
      message:
        '<p><strong>Até que dia esse quadro de aulas funcionou?</strong></p>' +
        '<input type="date" class="form-control" id="lessons-board-edit-archive-date" value="' + currentDate + '">',
      buttons: {
        cancel: {
          label: 'Cancelar',
          className: 'btn-default'
        },
        confirm: {
          label: 'Salvar',
          className: 'btn-primary',
          callback: function () {
            var archivedUntil = $('#lessons-board-edit-archive-date').val();
            if (!archivedUntil) {
              flashMessages.error('Informe até que dia esse quadro de aulas funcionou.');
              return false;
            }

            submitForm(url, 'patch', { archived_until: archivedUntil });
          }
        }
      }
    });
  });

  $(document).on('click', '.purge-lessons-board', function (e) {
    e.preventDefault();
    showPurgeDialog($(this).data('url'));
  });
})
