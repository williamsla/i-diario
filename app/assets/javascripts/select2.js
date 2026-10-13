$(document).ready(function(){
  _.each($('input.select2, input[class^=select2]').not('input.select2_remote'), function(element) {
    $(element).select2({
      formatResult: function(el) {
        var label = el.name || el.text || '';
        if (el.recordTypeLabel) {
          return "<div class='select2-user-result pedagogical-grade-option'>" +
            "<span class='pedagogical-grade-option__name'>" + label + "</span>" +
            "<span class='pedagogical-grade-option__type pedagogical-grade-option__type--" + (el.recordType || '') + "'>" +
            el.recordTypeLabel +
            "</span></div>";
        }
        return "<div class='select2-user-result'>" + label + "</div>";
      },
      formatSelection: function(el) {
        if(el.text) {
          return "<div class='select2-user-result'>" + el.text + "</div>";
        } else {
          return "<div class='select2-user-result'>" + el.name + "</div>";
        }
      },
      data: $(element).data('elements'),
      multiple: $(element).data('multiple'),
      allowClear: !$(element).data('hide-empty-element'),
      dropdownCssClass: $(element).data('dropdownCssClass') || '',
      matcher: function(term, text, option) {
        var defaultMatcher = $.fn.select2.defaults.matcher;
        if (defaultMatcher.call(this, term, text, option)) {
          return true;
        }

        return !!(option && (
          (option.course && defaultMatcher.call(this, term, option.course, option)) ||
          (option.recordTypeLabel && defaultMatcher.call(this, term, option.recordTypeLabel, option))
        ));
      },
      theme: 'classic'
    });

    if ($(element).data('multiple') && !$(element).data('without-json-parser') && !_.isEmpty($(element).val())){
      $(element).select2("val", JSON.parse($(element).val()));
    }
  });
});

$(function() {
  // Clear value when select empty element
  $('input.select2, input[class^=select2]').not('input.select2_remote').on('change', function(element) {
    if (element.val === "empty") {
      $(element.target).select2("val", "");
    }
  });
})
