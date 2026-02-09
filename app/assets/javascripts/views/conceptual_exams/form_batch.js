$(function () {
  'use strict';

  if ($('.concept-select').length && typeof $.fn.select2 !== 'undefined') {
    $('.concept-select').select2({
      width: '100%',
      allowClear: true,
      placeholder: ''
    });
  }
});
