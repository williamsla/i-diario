$(function () {
  'use strict';

  var $legendContainer = $('[data-event-batch-legend-container]'),
      $checkboxContainer = $('[data-event-batch-checkbox-container]'),
      $equivalentWeekdayContainer = $('[data-equivalent-weekday-batch-container]'),
      $startDate = $('#school_calendar_event_batch_start_date'),
      $endDate = $('#school_calendar_event_batch_end_date'),
      $equivalentWeekday = $('#school_calendar_event_batch_equivalent_weekday'),
      $eventType = $('#school_calendar_event_batch_event_type');

  var isEventTypeEqualTo = function(type) {
    return $eventType.val() === type;
  }

  var eventTypeIsBlank = function() {
    return isEventTypeEqualTo('');
  }

  var eventTypeIsExtraSchool = function() {
    return isEventTypeEqualTo('extra_school');
  }

  var eventTypeIsExtraSchoolWithoutFrequency = function() {
    return isEventTypeEqualTo('extra_school_without_frequency');
  }

  var eventTypeIsNoSchoolWithFrequency = function() {
    return isEventTypeEqualTo('no_school_with_frequency');
  }

  var parseFormDate = function(value) {
    if (_.isEmpty(value)) {
      return null;
    }

    var parts = value.split('/');

    if (parts.length === 3) {
      return new Date(parts[2], parts[1] - 1, parts[0]);
    }

    parts = value.split('-');

    if (parts.length === 3) {
      return new Date(parts[0], parts[1] - 1, parts[2]);
    }

    return null;
  };

  var isSaturdayDate = function(value) {
    var date = parseFormDate(value);

    return date && date.getDay() === 6;
  };

  var shouldShowEquivalentWeekday = function() {
    if (!eventTypeIsExtraSchool() && !eventTypeIsExtraSchoolWithoutFrequency()) {
      return false;
    }

    return isSaturdayDate($startDate.val()) && isSaturdayDate($endDate.val());
  };

  var toggleEquivalentWeekdayContainerVisibility = function() {
    if (shouldShowEquivalentWeekday()) {
      $equivalentWeekdayContainer.removeClass('hidden');
    } else {
      $equivalentWeekdayContainer.addClass('hidden');
      $equivalentWeekday.prop('required', false);
    }
  };

  var shouldHideLegend = function() {
    return eventTypeIsBlank() || eventTypeIsExtraSchool() || eventTypeIsNoSchoolWithFrequency();
  }

  var shouldShowCheckbox = function() {
    return eventTypeIsExtraSchool();
  }

   var togleLegendContainerVisibility = function() {
    if (shouldHideLegend()) {
      $legendContainer.addClass('hidden');
    } else {
      $legendContainer.removeClass('hidden');
    }
  }

  var togleCheckboxContainerVisibility = function() {
    if (shouldShowCheckbox()) {
      $checkboxContainer.removeClass('hidden');
    } else {
      $checkboxContainer.addClass('hidden');
    }
  }

  $eventType.on('change', togleLegendContainerVisibility);
  togleLegendContainerVisibility();

  $eventType.on('change', togleCheckboxContainerVisibility);
  togleCheckboxContainerVisibility();

  $eventType.on('change', toggleEquivalentWeekdayContainerVisibility);
  $startDate.on('change', toggleEquivalentWeekdayContainerVisibility);
  $endDate.on('change', toggleEquivalentWeekdayContainerVisibility);
  toggleEquivalentWeekdayContainerVisibility();
});
