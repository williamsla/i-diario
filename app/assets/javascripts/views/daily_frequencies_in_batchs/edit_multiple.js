$(document).ready( function() {
  $('[data-id="type_of_teaching"]').each( function (index, type_of_teaching) {
    $(type_of_teaching).on('change', function () {
      var inputs = $(this).closest('tr').find('[data-id="type_of_teaching_input"]')
      var value = $(this).val()
      inputs.each(function(index, input) {
        $(input).val(value)
      })
      var checkbox = $(this).closest('tr').find('[data-id="checkbox-id"]')
      var disabled = value != 1
      if (disabled == true) {
        checkbox.closest('label').addClass('state-disabled');
        checkbox.prop('disabled', disabled)
        checkbox.prop('checked', true)
      } else {
        checkbox.closest('label').removeClass('state-disabled');
        checkbox.prop('disabled', disabled)
      }
    }).trigger('change');

    var in_active_search = $(this).closest('tr').find('.in-active-search').size()
    var exempted_from_discipline = $(this).closest('tr').find('.exempted-student-from-discipline').size()
    var checkbox = $(this).closest('tr').find('[data-id="checkbox-id"]')

    if (in_active_search || exempted_from_discipline) {
      $(this).val(1)
      $(this).closest('label').addClass('state-disabled');
      $(this).prop('disabled', true)
      checkbox.closest('label').addClass('state-disabled');
      checkbox.prop('checked', true)
      checkbox.prop('disabled', true)
    }
  })
  $('.class-number-checkbox').each( function () {
    markGeneralCheckbox($(this).closest('td'))
  });
})

$(function () {
  var showConfirmation = $('#new_record').val() == 'true';

  // fix to checkboxes work correctly
  $('[name$="[present]"][type=hidden]').remove();

  var modalOptions = {
    title: 'Deseja salvar este lançamento antes de sair?',
    message: 'É necessário apertar o botão "Salvar" ' +
      'ao fim do lançamento de frequência em lote para que seja lançado com sucesso.',
    buttons: {
      confirm: { label: 'Salvar', className: 'btn new-save-style' },
      cancel: { label: 'Continuar sem salvar', className: 'btn new-delete-style' }
    }
  };

  $('a, button').on('click', function(e) {
    if (!showConfirmation) {
      return true;
    }

    e.preventDefault();
    showConfirmation = false;

    modalOptions = Object.assign(modalOptions, {
      callback: function(result) {
        if (result) {
          $('input[type=submit]').click();
        } else {
          e.target.click();
        }
      }
    });

    bootbox.confirm(modalOptions);
  });

  setTimeout(function() {
    $('.alert-success').hide();
  }, 10000);

  $('[name$="[present]"]').on('change', function (e) {
    showConfirmation = true;
  });

  $('.daily_frequency').on('submit', function (e) {
    showConfirmation = false;
  });

  $('.alert-success, .alert-danger').fadeTo(700, 0.1).fadeTo(700, 1.0);
});

$('.general-checkbox').on('change', function() {
  $(this).closest('td').find('.general-checkbox-icon').removeClass('half-checked')
  let checked = $(this).prop('checked')
  $(this).closest('td').find('.class-number-checkbox').prop('checked', checked)
  studentAbsencesCount($(this).closest('tr'))
})

$('.class-number-checkbox').on('change', function() {
  markGeneralCheckbox($(this).closest('td'))
  studentAbsencesCount($(this).closest('tr'))
});

function studentAbsencesCount(tr) {
  let count = tr.find('.class-number-checkbox:not(:checked)').length
  tr.find('.student-absences-count').text(count)
}

$('.date-collapse').on('click', function () {
  let index = $(this).index() + 1
  if ($(this).closest('table').find('tbody tr td:nth-child(' + index + ') .class-number-collapse').hasClass('hidden')) {
    $(this).closest('table').find('tbody tr td:nth-child(' + index + ') .class-number-collapse').removeClass('hidden')
    $(this).closest('table').find('tbody tr td:nth-child(' + index + ') .class-number-collapse').removeClass('collapsed')
    $(this).find('#icon-remove').removeClass('hidden')
    $(this).find('#icon-add').addClass('hidden')
    $(this).removeClass('collapsed')
  } else {
    $(this).closest('table').find('tbody tr td:nth-child(' + index + ') .class-number-collapse').addClass('hidden')
    $(this).closest('table').find('tbody tr td:nth-child(' + index + ') .class-number-collapse').addClass('collapsed')
    $(this).find('#icon-add').removeClass('hidden')
    $(this).find('#icon-remove').addClass('hidden')
    $(this).addClass('collapsed')
  }
});

function markGeneralCheckbox(td) {
  td.find('.general-checkbox').prop('checked', true)
  let all_checked = td.find('.class-number-checkbox:not(:checked)').length == 0
  let all_not_checked = td.find('.class-number-checkbox:is(:checked)').length == 0

  if (all_checked) {
    td.find('.general-checkbox-icon').removeClass('half-checked')
  } else {
    td.find('.general-checkbox-icon').addClass('half-checked')
  }

  if (all_not_checked) {
    td.find('.general-checkbox').prop('checked', false)
  }
}
