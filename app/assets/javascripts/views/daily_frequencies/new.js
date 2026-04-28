$(function () {
  window.classrooms = [];
  window.disciplines = [];
  window.avaliations = [];

  var $disciplineAbsenceFields = $(".discipline_absence_fields"),
      $globalAbsence = $("#daily_frequency_global_absence"),
      $examRuleNotFoundAlert = $('#exam-rule-not-found-alert');

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
      $.getJSON('/daily_frequencies/disciplines_for_frequency_date', {
        classroom_id: params.classroom_id,
        frequency_date: frequencyDate,
        period: periodParam()
      }).always(function (data) {
        callback(_.isArray(data) ? data : []);
      });
      return;
    }

    if (_.isEmpty(window.disciplines)) {
      $.getJSON('/disciplinas?' + $.param(params)).always(function (data) {
        window.disciplines = data;
        callback(window.disciplines);
      });
    } else {
      callback(window.disciplines);
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

  var autoFillClassNumbersBySchedule = function () {
    var disciplineId = getInputValue($discipline);
    var classroomId = getInputValue($classroom);
    var frequencyDate = getInputValue($frequencyDate);

    if (_.isEmpty(disciplineId) || _.isEmpty(classroomId) || _.isEmpty(frequencyDate)) {
      setClassNumbersOnField([]);
      return;
    }

    $.getJSON('/daily_frequencies/class_numbers_by_discipline', {
      classroom_id: classroomId,
      discipline_id: disciplineId,
      frequency_date: frequencyDate,
      period: periodParam()
    }).done(function (data) {
      setClassNumbersOnField(extractClassNumbersFromResponse(data));
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

  var applyDisciplinesToSelect = function (disciplines) {
    var selectedDisciplines = _.map(disciplines, function (discipline) {
      return { id: discipline['id'], text: discipline['description'] };
    });
    var previousDiscipline = getInputValue($discipline);
    $discipline.select2({ data: selectedDisciplines });
    if (previousDiscipline && _.find(selectedDisciplines, function (d) { return String(d.id) === String(previousDiscipline); })) {
      $discipline.select2('val', previousDiscipline);
    } else {
      $discipline.val('').trigger('change');
    }
  };

  var reloadDisciplinesForSelectedDate = function () {
    if (!$disciplineAbsenceFields.is(':visible')) {
      scheduleAutoFillClassNumbers();
      return;
    }

    var classroomId = getInputValue($classroom);
    var frequencyDate = getInputValue($frequencyDate);
    if (_.isEmpty(classroomId) || _.isEmpty(frequencyDate)) {
      scheduleAutoFillClassNumbers();
      return;
    }

    fetchDisciplines({ classroom_id: classroomId }, function (disciplines) {
      applyDisciplinesToSelect(disciplines);
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
      $('form input[type=submit]').removeClass('disabled');
      if(!$.isEmptyObject(examRule)){
        $examRuleNotFoundAlert.addClass('hidden');

        if(examRule.frequency_type == 2 || examRule.allow_frequency_by_discipline){
          $globalAbsence.val(0);
          $disciplineAbsenceFields.show();
          reloadDisciplinesForSelectedDate();
        }else{
          $globalAbsence.val(1);
          $disciplineAbsenceFields.hide();
          $discipline.val('').select2({ data: [] })
        }

      }else{
        $globalAbsence.val(0);
        $disciplineAbsenceFields.hide();

        // Display alert
        $examRuleNotFoundAlert.removeClass('hidden');

        // Disable form submit
        $('form input[type=submit]').addClass('disabled');
      }
    });
  }

  $classroom.on('change', function (e) {
    var params = {
      classroom_id: e.val
    };

    window.disciplines = [];
    window.avaliations = [];
    $discipline.val('').select2({ data: [] });
    $avaliation.val('').select2({ data: [] });

    if (!_.isEmpty(e.val)) {

      checkExamRule(params);

      fetchDisciplines(params, function (disciplines) {
        applyDisciplinesToSelect(disciplines);
      });
    }

    scheduleAutoFillClassNumbers();
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

    scheduleAutoFillClassNumbers();
  });

  $frequencyDate.on('change changeDate valid-date', function () {
    reloadDisciplinesForSelectedDate();
  });

  $disciplineAbsenceFields.hide();

  if($classroom.length && $classroom.val().length){
    checkExamRule({classroom_id: $classroom.val()});
  }

  if ($discipline.length && $discipline.val().length && $frequencyDate.length && $frequencyDate.val().length) {
    scheduleAutoFillClassNumbers();
  }
});
