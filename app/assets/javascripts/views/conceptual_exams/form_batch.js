$(function () {
  'use strict';

  var $conceptSelects = $('.concept-select');

  function initConceptSelects() {
    if (!$conceptSelects.length || typeof $.fn.select2 === 'undefined') {
      return;
    }

    $conceptSelects.select2({
      width: '56px',
      allowClear: true,
      placeholder: '',
      dropdownAutoWidth: true,
      dropdownCssClass: 'concept-select-dropdown',
      formatResult: function (result, _container, _query, escapeMarkup) {
        if (!result.id) {
          return result.text;
        }

        var fullName = result.element ? $(result.element).attr('title') : null;
        return escapeMarkup(fullName || result.text);
      },
      formatSelection: function (data, _container, escapeMarkup) {
        if (!data || data.text == null || data.text === '') {
          return undefined;
        }

        // Garante exibição da sigla com até 2 caracteres (ex.: PS, NS, S).
        var shortLabel = String(data.text).trim().substring(0, 2);
        return escapeMarkup(shortLabel);
      }
    });
  }

  function conceptSelectValue($select) {
    if ($select.data('select2')) {
      return $select.select2('val');
    }

    return $select.val();
  }

  function setConceptSelectValue($select, value) {
    if ($select.data('select2')) {
      $select.select2('val', value);
    } else {
      $select.val(value);
    }

    $select.trigger('change');
  }

  function isBlankConceptValue(value) {
    return value == null || String(value).length === 0;
  }

  function firstFilledConceptInRow($row) {
    var value = null;

    $row.find('.concept-select').each(function () {
      var current = conceptSelectValue($(this));

      if (!isBlankConceptValue(current)) {
        value = current;
        return false;
      }
    });

    return value;
  }

  function replicateFirstConcept($row, mode) {
    var value = firstFilledConceptInRow($row);

    $row.find('.concept-select').each(function () {
      var $select = $(this);

      if (mode === 'blank_only' && !isBlankConceptValue(conceptSelectValue($select))) {
        return;
      }

      setConceptSelectValue($select, value);
    });
  }

  function askReplicateMode($button, onChoose) {
    if (typeof bootbox === 'undefined') {
      var useAll = window.confirm($button.data('dialog-message') + '\n\nOK = todas as disciplinas\nCancelar = somente em branco');
      onChoose(useAll ? 'all' : 'blank_only');
      return;
    }

    bootbox.dialog({
      title: $button.data('dialog-title'),
      message: $button.data('dialog-message'),
      buttons: {
        cancel: {
          label: $button.data('label-cancel'),
          className: 'btn-default'
        },
        blankOnly: {
          label: $button.data('label-blank'),
          className: 'btn-info',
          callback: function () {
            onChoose('blank_only');
          }
        },
        all: {
          label: $button.data('label-all'),
          className: 'btn-primary',
          callback: function () {
            onChoose('all');
          }
        }
      }
    });
  }

  initConceptSelects();

  $('#conceptual_exam_batch_table').on('click', '.batch-replicate-btn', function (event) {
    event.preventDefault();

    var $button = $(this);
    var $row = $button.closest('tr');
    var value = firstFilledConceptInRow($row);

    if (isBlankConceptValue(value)) {
      window.alert($button.data('empty-message'));
      return;
    }

    askReplicateMode($button, function (mode) {
      replicateFirstConcept($row, mode);
    });
  });
});
