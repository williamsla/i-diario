$(function () {
  'use strict';

  var $form = $('#knowledge-area-content-record-form, #discipline-content-record-form');
  if (!$form.length) {
    return;
  }

  var studentDataUrl = $form.data('student-data-url') || $form.attr('data-student-data-url');
  var $student = $('[id$="_content_record_attributes_student_id"]');
  var $contents = $('[id$="_content_record_attributes_contents_tags"]');
  var $objectives = $('[id$="_content_record_attributes_objectives_tags"]');
  var $context = $('#aee-pei-context');
  var $contextBody = $('#aee-pei-context-body');
  var isPersistedRecord = !!$('[id$="_content_record_attributes_id"]').val();
  var requestSeq = 0;

  if (!$student.length || !studentDataUrl) {
    return;
  }

  var escapeHtml = function (value) {
    return $('<div>').text(value || '').html();
  };

  var sectionHtml = function (title, value) {
    if (!value) {
      return '';
    }

    return '<p><strong>' + escapeHtml(title) + ':</strong> ' + escapeHtml(value) + '</p>';
  };

  var showContext = function (data) {
    if (!$context.length) {
      return;
    }

    if (!data || (!data.goals && !data.strategies && !data.resources)) {
      $contextBody.html('<p>' + escapeHtml($context.data('empty-message')) + '</p>');
      $context.show();
      return;
    }

    $contextBody.html(
      sectionHtml($context.data('goals-label'), data.goals) +
      sectionHtml($context.data('strategies-label'), data.strategies) +
      sectionHtml($context.data('resources-label'), data.resources)
    );
    $context.show();
  };

  var appendTags = function ($field, values) {
    if (!$field.length || !values || !values.length) {
      return;
    }

    var listId = $field.attr('id').indexOf('objectives') >= 0 ? '#objectives-list' : '#contents-list';
    if ($(listId + ' li:visible').length) {
      return;
    }

    $.each(values, function (_index, value) {
      if (!value) {
        return;
      }

      $field.trigger({ type: 'change', val: [value] });
    });
  };

  var fillFromPei = function (studentId) {
    var seq = ++requestSeq;

    if (!studentId) {
      $context.hide();
      return;
    }

    $.ajax({
      url: studentDataUrl,
      dataType: 'json',
      data: { student_id: studentId },
      success: function (data) {
        if (seq !== requestSeq) {
          return;
        }

        showContext(data);

        if (isPersistedRecord) {
          return;
        }

        setTimeout(function () {
          if (seq !== requestSeq) {
            return;
          }

          appendTags($contents, data.contents);
          appendTags($objectives, data.objectives);
        }, 1000);
      }
    });
  };

  $student.on('change', function () {
    fillFromPei($student.select2('val') || $student.val());
  });

  var initialStudentId = $student.select2('val') || $student.val();
  if (initialStudentId && !isPersistedRecord) {
    fillFromPei(initialStudentId);
  }
});
