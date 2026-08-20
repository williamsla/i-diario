$(function () {
  'use strict';

  var $form = $('#knowledge_area_teaching_plan, #discipline_teaching_plan');
  if (!$form.length) {
    return;
  }

  var prefix = $form.attr('id');
  var studentDataUrl = $form.data('student-data-url') || $form.attr('data-student-data-url');
  var $student = $('#' + prefix + '_teaching_plan_attributes_student_id');

  if (!$student.length || !studentDataUrl) {
    return;
  }

  var fields = {
    student_characteristics: $('#' + prefix + '_teaching_plan_attributes_aee_teaching_plan_detail_attributes_student_characteristics'),
    methodology: $('#' + prefix + '_teaching_plan_attributes_methodology')
  };

  var isEmpty = function ($field) {
    if (!$field.length) {
      return true;
    }

    if ($field.next('.note-editor').length && typeof $field.summernote === 'function') {
      var html = $field.summernote('code') || '';
      return $.trim($('<div>').html(html).text()) === '';
    }

    return !$.trim($field.val() || '');
  };

  var fillIfEmpty = function ($field, value) {
    if (!value || !isEmpty($field)) {
      return false;
    }

    if ($field.next('.note-editor').length && typeof $field.summernote === 'function') {
      $field.summernote('code', value);
      return true;
    }

    $field.val(value);
    return true;
  };

  var fillFromCaseStudy = function (studentId) {
    if (!studentId) {
      return;
    }

    $.ajax({
      url: studentDataUrl,
      dataType: 'json',
      data: { student_id: studentId },
      success: function (data) {
        var filled = fillIfEmpty(fields.student_characteristics, data.student_characteristics);
        filled = fillIfEmpty(fields.methodology, data.methodology) || filled;

        if (filled) {
          $('.aee-prefill-notice').show();
        }
      }
    });
  };

  $student.on('change', function () {
    fillFromCaseStudy($student.select2('val') || $student.val());
  });

  var initialStudentId = $student.select2('val') || $student.val();
  if (initialStudentId) {
    fillFromCaseStudy(initialStudentId);
  }
});
