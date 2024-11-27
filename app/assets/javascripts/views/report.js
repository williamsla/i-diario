$(function () {
  'use strict';

  $(document).ready(function() {
    initializeForm();
  });

  function initializeForm() {
    // $('#send-form').attr("disabled", true);    
    $('form input[type=submit]').removeClass('disabled');
  }
});
