$(function () {
  window.classrooms = [];
  window.disciplines = [];
  window.avaliations = [];

  var $form = $('#daily-frequency-new-form'),
      apiPaths = {
        disciplinesForDate: $form.data('disciplinesForDateUrl'),
        scheduleForDate: $form.data('scheduleForDateUrl'),
        fetchFrequencyType: $form.data('fetchFrequencyTypeUrl'),
        classNumbersByDiscipline: $form.data('classNumbersByDisciplineUrl')
      },
      $disciplineField = $(".discipline_field"),
      $classNumbersField = $(".class_numbers_field"),
      $globalAbsence = $("#daily_frequency_global_absence"),
      $examRuleNotFoundAlert = $('#exam-rule-not-found-alert'),
      $disciplinesEmptyAlert = $('#disciplines-empty-alert'),
      $disciplinesEmptyMessage = $('#disciplines-empty-message'),
      $frequencyDateHint = $('#frequency-date-hint'),
      isByDisciplineFrequency = false;

  var fetchClassrooms = function (params, callback) {
    if (_.isEmpty(window.classrooms)) {
      $.getJSON(Routes.classrooms_pt_br_path(params)).always(function (data) {
        window.classrooms = data;
        callback(window.classrooms);
      });
    } else {
      callback(window.classrooms);
    }
  };

  var fetchAvaliations = function (params, callback) {
    if (_.isEmpty(window.avaliations)) {
      $.getJSON('/teacher_avaliations?' + $.param(params)).always(function (data) {
        window.avaliations = data;
        callback(window.avaliations);
      });
    } else {
      callback(window.avaliations);
    }
  };

  var fetchExamRule = function (params, callback) {
    $.getJSON('/exam_rules?' + $.param(params)).always(function (data) {
      callback(data);
    });
  };

  var fetchFrequencyType = function (params, callback) {
    $.getJSON(apiPaths.fetchFrequencyType, params).always(function (data) {
      callback(data);
    });
  };

  var $classroom  = $('#daily_frequency_classroom_id');
  var $discipline = $('#daily_frequency_discipline_id');
  var $avaliation = $('#daily_frequency_avaliation_id');
  var $classNumbers = $('#class_numbers');
  var $frequencyDate = $('#daily_frequency_frequency_date');
  var autoFillTimeout = null;

  var periodParam = function () {
    var $period = $('#daily_frequency_period');
    return $period.length ? $period.val() : '';
  };

  // AMS / responders podem envolver a lista (ex.: { daily_frequencies: [...] }).
  var normalizeDisciplinesPayload = function (raw) {
    var data = raw && raw.responseJSON != null ? raw.responseJSON : raw;

    if (data && _.isArray(data.disciplines)) {
      return { disciplines: data.disciplines, message: data.message || null };
    }
    if (_.isArray(data)) {
      return { disciplines: data, message: null };
    }
    if (data && _.isArray(data.daily_frequencies)) {
      return { disciplines: data.daily_frequencies, message: null };
    }
    if (data && _.isArray(data.disciplines)) {
      return { disciplines: data.disciplines, message: null };
    }
    return { disciplines: [], message: null };
  };

  var getInputValue = function ($input) {
    if (!$input || !$input.length) {
      return '';
    }

    try {
      if ($input.data('select2')) {
        return $input.select2('val');
      }
    } catch (e) {}

    return $input.val();
  };

  var fetchDisciplines = function (params, callback) {
    var frequencyDate = getInputValue($frequencyDate);
    if (!_.isEmpty(params.classroom_id) && !_.isEmpty(frequencyDate)) {
      $.getJSON(apiPaths.disciplinesForDate, {
        classroom_id: params.classroom_id,
        frequency_date: frequencyDate,
        period: periodParam()
      }).done(function (raw) {
        callback(normalizeDisciplinesPayload(raw));
      }).fail(function () {
        callback({
          disciplines: [],
          message: 'Não foi possível carregar as disciplinas para a data selecionada. Tente novamente.'
        });
      });
      return;
    }

    if (_.isEmpty(window.disciplines)) {
      $.getJSON('/disciplinas?' + $.param(params)).always(function (raw) {
        var payload = normalizeDisciplinesPayload(raw);
        window.disciplines = payload.disciplines;
        callback(payload);
      });
    } else {
      callback({ disciplines: window.disciplines, message: null });
    }
  };

  var setClassNumbersOnField = function (classNumbers) {
    var normalizedNumbers = _.chain(classNumbers || [])
      .map(function (number) { return parseInt(number, 10); })
      .filter(function (number) { return !isNaN(number); })
      .uniq()
      .sortBy(function (number) { return number; })
      .value();

    var selectedElements = _.map(normalizedNumbers, function (number) {
      var numberAsString = number.toString();
      return { id: numberAsString, name: numberAsString, text: numberAsString };
    });
    var selectedIds = _.map(selectedElements, function (element) { return element.id; });

    // Select2 legado: popular opções selecionadas e valor atual explicitamente.
    $classNumbers.select2('data', selectedElements);
    $classNumbers.select2('val', selectedIds);
    $classNumbers.val(selectedIds.join(','));
    $classNumbers.trigger('change');
  };

  var extractClassNumbersFromResponse = function (response) {
    if (_.isArray(response)) {
      return response;
    }

    if (!response || !_.isObject(response)) {
      return [];
    }

    if (_.isArray(response.class_numbers)) {
      return response.class_numbers;
    }

    if (_.isArray(response.daily_frequencies)) {
      return response.daily_frequencies;
    }

    return [];
  };

  var applyPeriodFromScheduleResponse = function (data) {
    var $period = $('#daily_frequency_period');
    if (!$period.length || !data || _.isArray(data)) {
      return;
    }
    if (data.period === undefined || data.period === null || data.period === '') {
      return;
    }
    $period.val(String(data.period));
  };

  var autoFillClassNumbersBySchedule = function () {
    var disciplineId = getInputValue($discipline);
    var classroomId = getInputValue($classroom);
    var frequencyDate = getInputValue($frequencyDate);

    if (_.isEmpty(disciplineId) || _.isEmpty(classroomId) || _.isEmpty(frequencyDate)) {
      setClassNumbersOnField([]);
      return;
    }

    $.getJSON(apiPaths.classNumbersByDiscipline, {
      classroom_id: classroomId,
      discipline_id: disciplineId,
      frequency_date: frequencyDate
    }).done(function (data) {
      setClassNumbersOnField(extractClassNumbersFromResponse(data));
      applyPeriodFromScheduleResponse(data);
    }).fail(function () {
      setClassNumbersOnField([]);
    });
  };

  var scheduleAutoFillClassNumbers = function () {
    if (autoFillTimeout) {
      clearTimeout(autoFillTimeout);
    }

    autoFillTimeout = setTimeout(function () {
      autoFillClassNumbersBySchedule();
    }, 150);
  };

  var toggleFrequencyDateAlert = function (message) {
    if (message) {
      $disciplinesEmptyMessage.text(message);
      $disciplinesEmptyAlert.removeClass('hidden');
      $frequencyDateHint.text(message).removeClass('hidden');
      syncSubmitButtonState();
    } else {
      $disciplinesEmptyAlert.addClass('hidden');
      $disciplinesEmptyMessage.text('');
      $frequencyDateHint.text('').addClass('hidden');
      syncSubmitButtonState();
    }
  };

  var syncSubmitButtonState = function () {
    if (!$examRuleNotFoundAlert.hasClass('hidden') || !$disciplinesEmptyAlert.hasClass('hidden')) {
      $('form input[type=submit]').addClass('disabled');
      return;
    }

    $('form input[type=submit]').removeClass('disabled');
  };

  var applyDisciplinesToSelect = function (payload) {
    var disciplines = payload.disciplines || [];
    var selectedDisciplines = _.map(disciplines, function (discipline) {
      var label = discipline.description || discipline.name || discipline.text || '';
      return { id: discipline.id, text: label, name: label };
    });
    var previousDiscipline = getInputValue($discipline);
    $discipline.select2({ data: selectedDisciplines });
    if (previousDiscipline && _.find(selectedDisciplines, function (d) { return String(d.id) === String(previousDiscipline); })) {
      $discipline.select2('val', previousDiscipline);
    } else {
      $discipline.val('').trigger('change');
    }
    toggleFrequencyDateAlert(payload.message);
  };

  var reloadScheduleForSelectedDate = function () {
    var classroomId = getInputValue($classroom);
    var frequencyDate = getInputValue($frequencyDate);

    if (_.isEmpty(classroomId) || _.isEmpty(frequencyDate)) {
      toggleFrequencyDateAlert(null);
      return;
    }

    $.getJSON(apiPaths.scheduleForDate, {
      classroom_id: classroomId,
      frequency_date: frequencyDate
    }).done(function (data) {
      toggleFrequencyDateAlert(data && data.available === false ? data.message : null);
    }).fail(function () {
      toggleFrequencyDateAlert('Não foi possível verificar o quadro de horários para a data selecionada. Tente novamente.');
    });
  };

  var reloadFrequencyDateAvailability = function () {
    if (isByDisciplineFrequency) {
      reloadDisciplinesForSelectedDate();
      return;
    }

    reloadScheduleForSelectedDate();
  };

  var reloadDisciplinesForSelectedDate = function () {
    if (!isByDisciplineFrequency) {
      reloadScheduleForSelectedDate();
      return;
    }

    var classroomId = getInputValue($classroom);
    var frequencyDate = getInputValue($frequencyDate);
    if (_.isEmpty(classroomId) || _.isEmpty(frequencyDate)) {
      scheduleAutoFillClassNumbers();
      return;
    }

    fetchDisciplines({ classroom_id: classroomId }, function (payload) {
      applyDisciplinesToSelect(payload);
      scheduleAutoFillClassNumbers();
    });
  };

  $('#daily_frequency_unity_id').on('change', function (e) {
    var params = {
      filter: {
        by_unity: e.val
      },
      find_by_current_teacher: true
    };

    window.classrooms = [];
    window.disciplines = [];
    window.avaliations = [];
    $classroom.val('').select2({ data: [] });
    $discipline.val('').select2({ data: [] });
    $avaliation.val('').select2({ data: [] });

    if (!_.isEmpty(e.val)) {
      fetchClassrooms(params, function (classrooms) {
        var selectedClassrooms = _.map(classrooms, function (classroom) {
          return { id:classroom['id'], text: classroom['description'] };
        });

        $classroom.select2({
          data: selectedClassrooms
        });
      });
    }
  });

  var checkExamRule = function(params){
    fetchExamRule(params, function(data){
      var examRule = data.exam_rule;
      if(!$.isEmptyObject(examRule)){
        $examRuleNotFoundAlert.addClass('hidden');

        if(examRule.frequency_type == 2 || examRule.allow_frequency_by_discipline){
          isByDisciplineFrequency = true;
          $globalAbsence.val(0);
          $disciplineField.show();
          reloadDisciplinesForSelectedDate();
        }else{
          isByDisciplineFrequency = false;
          $globalAbsence.val(1);
          $disciplineField.hide();
          $classNumbersField.hide();
          $discipline.val('').trigger('change');
          $classNumbers.val('').trigger('change');
          $discipline.select2({ data: [] });
          reloadScheduleForSelectedDate();
        }
      }else{
        $globalAbsence.val(0);
        $disciplineField.hide();
        $classNumbersField.hide();

        // Display alert
        $examRuleNotFoundAlert.removeClass('hidden');

        // Disable form submit
        $('form input[type=submit]').addClass('disabled');
      }
    });
  }

  var toggleClassNumbersByFrequencyType = function () {
    var classroomId = getInputValue($classroom);
    var disciplineId = getInputValue($discipline);

    if (_.isEmpty(classroomId) || _.isEmpty(disciplineId)) {
      $classNumbersField.hide();
      $classNumbers.val('').trigger('change');
      return;
    }

    fetchFrequencyType({
      classroom_id: classroomId,
      discipline_id: disciplineId
    }, function (frequencyType) {
      var normalizedFrequencyType = parseInt(frequencyType, 10);

      if (normalizedFrequencyType === 2) {
        $classNumbersField.show();
        scheduleAutoFillClassNumbers();
      } else {
        $classNumbersField.hide();
        $classNumbers.val('').trigger('change');
      }
    });
  };

  $classroom.on('change', function (e) {
    var params = {
      classroom_id: e.val
    };

    window.disciplines = [];
    window.avaliations = [];
    $discipline.val('').select2({ data: [] });
    $avaliation.val('').select2({ data: [] });
    toggleFrequencyDateAlert(null);

    if (!_.isEmpty(e.val)) {
      checkExamRule(params);
    }

    toggleClassNumbersByFrequencyType();
  });

  $('#daily_frequency_discipline_id').on('change', function (e) {
    var params = {
      discipline_id: e.val,
      classroom_id: $classroom.val()
    };

    window.avaliations = [];
    $avaliation.val('').select2({ data: [] });

    if (!_.isEmpty(e.val)) {
      fetchAvaliations(params, function (avaliations) {
        var selectedAvaliations = _.map(avaliations, function (avaliation) {
          return { id: avaliation['id'], text: avaliation['description'] };
        });

        $avaliation.select2({
          data: selectedAvaliations
        });
      });
    }

    toggleClassNumbersByFrequencyType();
  });

  $frequencyDate.on('change changeDate valid-date', function () {
    reloadFrequencyDateAvailability();
  });

  $disciplineField.hide();
  $classNumbersField.hide();

  if($classroom.length && $classroom.val().length){
    checkExamRule({classroom_id: $classroom.val()});
  }

  if ($discipline.length && $discipline.val().length && $frequencyDate.length && $frequencyDate.val().length) {
    toggleClassNumbersByFrequencyType();
  }
});
