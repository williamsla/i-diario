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

  $(document).on('click', '.archive-lessons-board', function (e) {
    e.preventDefault();

    var url = $(this).data('url');
    if (!url) {
      return;
    }

    var today = new Date().toISOString().slice(0, 10);

    bootbox.dialog({
      title: 'Arquivar quadro de aula',
      message:
        '<p><strong>Até que dia esse quadro de aulas funcionou?</strong></p>' +
        '<input type="date" class="form-control" id="lessons-board-archive-date" value="' + today + '">',
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

            var form = $('<form>', { method: 'POST', action: url });
            form.append($('<input>', { type: 'hidden', name: '_method', value: 'delete' }));
            form.append($('<input>', {
              type: 'hidden',
              name: 'authenticity_token',
              value: $('meta[name="csrf-token"]').attr('content')
            }));
            form.append($('<input>', { type: 'hidden', name: 'archived_until', value: archivedUntil }));
            form.appendTo('body').submit();
          }
        }
      }
    });
  });
})
