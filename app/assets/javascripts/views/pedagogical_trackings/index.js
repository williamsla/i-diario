var frequency_chart_ctx = document.getElementById('frequency_chart').getContext('2d');
var content_record_chart_ctx = document.getElementById('content_record_chart').getContext('2d');

var done_frequencies_percentage = $('#done_frequencies_percentage').val();
var done_content_records_percentage = $('#done_content_records_percentage').val();
var unknown_teachers = $('#unknown_teachers').val();

function textToCenter() {
  Chart.pluginService.register({
    beforeDraw: function(chart) {
      if (chart.config.options.elements.center) {
        // Get ctx from string
        var ctx = chart.chart.ctx;

        // Get options from the center object in options
        var centerConfig = chart.config.options.elements.center;
        var fontStyle = centerConfig.fontStyle || 'Arial';
        var txt = centerConfig.text;
        var color = centerConfig.color || '#000';
        var maxFontSize = centerConfig.maxFontSize || 75;
        var sidePadding = centerConfig.sidePadding || 20;
        var sidePaddingCalculated = (sidePadding / 100) * (chart.innerRadius * 2)
        // Start with a base font of 30px
        ctx.font = "30px " + fontStyle;

        // Get the width of the string and also the width of the element minus 10 to give it 5px side padding
        var stringWidth = ctx.measureText(txt).width;
        var elementWidth = (chart.innerRadius * 2) - sidePaddingCalculated;

        // Find out how much the font can grow in width.
        var widthRatio = elementWidth / stringWidth;
        var newFontSize = Math.floor(30 * widthRatio);
        var elementHeight = (chart.innerRadius * 2);

        // Pick a new font size so it will not be larger than the height of label.
        var fontSizeToUse = Math.min(newFontSize, elementHeight, maxFontSize);
        var minFontSize = centerConfig.minFontSize;
        var lineHeight = centerConfig.lineHeight || 25;
        var wrapText = false;

        if (minFontSize === undefined) {
          minFontSize = 20;
        }

        if (minFontSize && fontSizeToUse < minFontSize) {
          fontSizeToUse = minFontSize;
          wrapText = true;
        }

        // Set font settings to draw it correctly.
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        var centerX = ((chart.chartArea.left + chart.chartArea.right) / 2);
        var centerY = ((chart.chartArea.top + chart.chartArea.bottom) / 2);
        ctx.font = fontSizeToUse + "px " + fontStyle;
        ctx.fillStyle = color;

        if (!wrapText) {
          ctx.fillText(txt, centerX, centerY);
          return;
        }

        var words = txt.split(' ');
        var line = '';
        var lines = [];

        // Break words up into multiple lines if necessary
        for (var n = 0; n < words.length; n++) {
          var testLine = line + words[n] + ' ';
          var metrics = ctx.measureText(testLine);
          var testWidth = metrics.width;
          if (testWidth > elementWidth && n > 0) {
            lines.push(line);
            line = words[n] + ' ';
          } else {
            line = testLine;
          }
        }

        // Move the center up depending on line height and number of lines
        centerY -= (lines.length / 2) * lineHeight;

        for (var n = 0; n < lines.length; n++) {
          ctx.fillText(lines[n], centerX, centerY);
          centerY += lineHeight;
        }
        //Draw text in center
        ctx.fillText(line, centerX, centerY);
      }
    }
  });
}

function clear_empty(element) {
  if (element.val === "empty") {
    $(element.target).select2("val", "");
  }
}

function build_pie_chart(ctx, done_percentage, unknown_teachers = null){
  var labels = ['% Não Lançados', '% Lançados']
  var data = [(100 - done_percentage).toFixed(2), done_percentage]
  var backgroundColor = ['rgba(191, 74, 74, 1)', 'rgba(133, 191, 74, 1)']
  var borderColor = ['rgba(191, 74, 74, 1)', 'rgba(133, 191, 74, 1)']

  if (unknown_teachers) {
    labels.push('% Período não mapeado');
    data = [(100 - (parseFloat(done_percentage) + parseFloat(unknown_teachers))).toFixed(2), done_percentage, unknown_teachers]
    backgroundColor.push('rgba(229, 201, 98, 1)');
    borderColor.push('rgba(229, 201, 98, 1)');
  }

  textToCenter()

  new Chart(ctx, {
      type: 'doughnut',
      data: {
          labels: labels,
          datasets: [{
              data: data,
              backgroundColor: backgroundColor,
              borderColor: borderColor,
              borderWidth: 0.5
          }]
      },
      options: {
        cutoutPercentage: 70,
        elements: {
          center: {
            text: 'Você selecionou um total de ' + $('#school_days').val() + ' dias letivos',
            color: '#888888', // Default is #000000
            fontStyle: 'Arial', // Default is Arial
            sidePadding: 20, // Default is 20 (as a percentage)
            minFontSize: 15, // Default is 20 (in px), set to false and text will not wrap.
            lineHeight: 15 // Default is 25 (in px), used for when text wraps
          }
        }
      }
  });
}

$(document).ready( function() {
  let beta_title = 'Este recurso ainda está em processo de desenvolvimento e pode apresentar problemas'
  let img_src = $('#image-beta').attr('src');
  $('.fa-pie-chart').closest('h2').after('<img src="' + img_src + '" class="beta-badge" style="margin-bottom: 9px; margin-left: 5px" title="' + beta_title + '">');
})

build_pie_chart(frequency_chart_ctx, done_frequencies_percentage, unknown_teachers);
build_pie_chart(content_record_chart_ctx, done_content_records_percentage);

$('#search_unity_id').on('change', function(e){
  clear_empty(e);
  $('form.filter_tracking_search_form').trigger("submit");
});
$('#search_start_date').on('change', function(e){
  clear_empty(e);
  $('form.filter_tracking_search_form').trigger("submit");
});
$('#search_end_date').on('change', function(e){
  clear_empty(e);
  $('form.filter_tracking_search_form').trigger("submit");
});

var unity_id = $('#unity_id').val();
var start_date = $('#start_date').val();
var end_date = $('#end_date').val();
var step_start_date = $('#step_start_date').val();
var step_end_date = $('#step_end_date').val();

if (unity_id) {
  $('#search_unity_id').val(unity_id);
  $('#section-frequency').hide();
  $('#section-content').hide();
} else {
  $('#section-frequency').hide();
  $('#section-content').hide();
}


if (start_date) {
  $('#search_start_date').val(start_date);
} else {
  $('#search_start_date').attr('placeholder', step_start_date)
}

if (end_date) {
  $('#search_end_date').val(end_date);
} else {
  $('#search_end_date').attr('placeholder', step_end_date)
}

if (_.isEmpty($('#filter_frequency_operator').val())){
  $('#filter_frequency_percentage').attr('readonly', true).val('');
}
if (_.isEmpty($('#filter_content_record_operator').val())){
  $('#filter_content_record_percentage').attr('readonly', true).val('');
}

var typingTimer;

$('#filter_frequency_percentage, \
  #filter_content_record_percentage, \
  #search_teacher_frequency_percentage, \
  #search_teacher_content_record_percentage').keyup(function() {
  clearTimeout(typingTimer);
  var self = $(this);
  typingTimer = setTimeout(function(){
    self.trigger('change');
  }, 1200);
});

$('form.percent_filterable_search_form input, form.percent_filterable_search_form input.select2').on('change',
  function (e){
    clear_empty(e);

    if (this.id == 'filter_frequency_operator') {
      if (_.isEmpty($('#filter_frequency_operator').val())){
        $('#filter_frequency_percentage').attr('readonly', true).val('');
      } else {
        $('#filter_frequency_percentage').removeAttr('readonly');
        $('#filter_frequency_percentage').focus();
      }
    }

    if (this.id == 'filter_content_record_operator') {
      if (_.isEmpty($('#filter_content_record_operator').val())){
        $('#filter_content_record_percentage').attr('readonly', true).val('');
      } else {
        $('#filter_content_record_percentage').removeAttr('readonly');
        $('#filter_content_record_percentage').focus();
      }
    }

    if ((this.id == 'filter_frequency_percentage' &&
         _.isEmpty($('#filter_frequency_percentage').val())) ||
        (this.id == 'filter_content_record_percentage' &&
         _.isEmpty($('#filter_content_record_percentage').val()))) {
      return false;
    }

    if ((this.id == 'filter_frequency_operator' &&
         _.isEmpty($('#filter_frequency_percentage').val()) &&
         !($('#filter_frequency_percentage').attr('readonly'))) ||
        (this.id == 'filter_content_record_operator' &&
         _.isEmpty($('#filter_content_record_percentage').val()) &&
         !($('#filter_frequency_percentage').attr('readonly')))) {
      return false;
    }

    $.get(
      $('form.percent_filterable_search_form').attr('action'),
      $('form.percent_filterable_search_form').serialize(),
      null,
      'script'
    );

    return false;
  }
);

function openResumeModal(unityId, classroomId) {
  const modal = document.getElementById("resumeModal");
  if (!modal) return;

  modal.style.display = "flex";

  const downloadBtn = document.getElementById("downloadXlsxBtn");
  downloadBtn.onclick = function() {
    const url = '/pedagogical_trackings/resume_xlsx?unity_id=' + unityId + '&classroom_id=' + (classroomId || 0);
    window.location.href = url;
  }

  document.getElementById("resumeModalBody").innerHTML =
    "<p class='pedagogical-modal__loading'>Carregando resumo...</p>";

  fetch('/pedagogical_trackings/resume_modal?unity_id=' + unityId + '&classroom_id=' + (classroomId || 0))
    .then(response => response.text())
    .then(html => {
      document.getElementById("resumeModalBody").innerHTML = html;
      initResumeReportFilters();
    })
    .catch(err => {
      console.error("Erro ao carregar modal:", err);
      document.getElementById("resumeModalBody").innerHTML =
        "<p style='color:red;'>Erro ao carregar o resumo.</p>";
    });
}

function initResumeReportFilters() {
  var $report = $('#resumeReport');
  if (!$report.length) return;

  function teacherCellHtml(label, pending) {
    var pendingClass = pending ? ' resume-table__sticky--teacher-pending' : '';
    return '<td class="resume-table__sticky resume-table__sticky--teacher resume-table__text' +
      pendingClass + '" rowspan="1">' + $('<div>').text(label || '').html() + '</td>';
  }

  function flattenTeacherCells($table) {
    $table.find('.resume-table__classroom-group').each(function() {
      $(this).find('.resume-table__data-row').each(function() {
        var $row = $(this);
        var label = $row.attr('data-teacher-label') || '';
        var pending = String($row.data('teacher-pending')) === 'true';
        var $cell = $row.children('.resume-table__sticky--teacher');

        if ($cell.length) {
          $cell.attr('rowspan', 1).show();
          $cell.text(label);
          $cell.toggleClass('resume-table__sticky--teacher-pending', pending);
        } else {
          $row.prepend(teacherCellHtml(label, pending));
        }
      });
    });
  }

  function mergeTeacherCells($table) {
    $table.find('.resume-table__classroom-group').each(function() {
      var currentTeacher = null;
      var $firstCell = null;
      var count = 0;

      $(this).find('.resume-table__data-row').removeClass('resume-table__data-row--teacher-start');

      $(this).find('.resume-table__data-row:visible').each(function() {
        var $row = $(this);
        var teacher = String($row.data('teacher') || '');
        var $cell = $row.children('.resume-table__sticky--teacher');

        if (teacher === currentTeacher && $firstCell) {
          $cell.remove();
          count += 1;
          $firstCell.attr('rowspan', count);
        } else {
          currentTeacher = teacher;
          $firstCell = $cell;
          count = 1;
          $row.addClass('resume-table__data-row--teacher-start');
          if ($firstCell.length) {
            $firstCell.attr('rowspan', 1).show();
          }
        }
      });
    });
  }

  function applySearchFilter() {
    var $table = $('#resumeTable');
    var search = $.trim($report.find('#resumeSearchInput').val() || '').toLowerCase();
    var visibleRows = 0;

    flattenTeacherCells($table);

    $table.find('.resume-table__classroom-group').each(function() {
      var $group = $(this);
      var groupVisible = 0;

      $group.find('.resume-table__data-row').each(function() {
        var $row = $(this);
        var teacher = String($row.data('teacher') || '');
        var discipline = String($row.data('discipline') || '');
        var classroom = String($row.data('classroom') || '');
        var visible = !search ||
          teacher.indexOf(search) !== -1 ||
          discipline.indexOf(search) !== -1 ||
          classroom.indexOf(search) !== -1;

        $row.toggle(visible);
        if (visible) groupVisible += 1;
      });

      $group.toggle(groupVisible > 0);
      visibleRows += groupVisible;
    });

    mergeTeacherCells($table);

    $report.find('.resume-report__empty--filtered').prop('hidden', visibleRows > 0);
    $report.find('.resume-report__table-wrap').toggle(visibleRows > 0);
  }

  $report.find('#resumeSearchInput').on('input', applySearchFilter);

  $report
    .on('mouseenter', '.resume-table__data-row', function() {
      var $row = $(this);
      var $group = $row.closest('.resume-table__classroom-group');
      var teacher = String($row.data('teacher') || '');

      $group.find('.is-teacher-hover').removeClass('is-teacher-hover');
      $row.addClass('is-teacher-hover');

      $group.find('.resume-table__data-row').filter(function() {
        return String($(this).data('teacher') || '') === teacher &&
          $(this).children('.resume-table__sticky--teacher').length > 0;
      }).children('.resume-table__sticky--teacher').addClass('is-teacher-hover');
    })
    .on('mouseleave', '.resume-table__classroom-group', function() {
      $(this).find('.is-teacher-hover').removeClass('is-teacher-hover');
    });
}

function closeResumeModal(event) {
  if (event) event.preventDefault();

  const modal = document.getElementById("resumeModal");
  if (!modal) return;
  modal.style.display = "none";
  document.getElementById("resumeModalBody").innerHTML = "";
}

// Variáveis globais para armazenar os parâmetros do modal
let currentFrequencyModalParams = {
  unityId: null,
  classroomId: null,
  mainFilter: 'low_frequency_only',
  selectedClassifications: ['Abaixo do Mínimo', 'Crítico']
};

function openFrequencyReportModal(unityId, classroomId) {
  const modal = document.getElementById("frequencyReportModal");
  if (!modal) return;

  // Armazenar parâmetros para uso no filtro
  currentFrequencyModalParams.unityId = unityId;
  currentFrequencyModalParams.classroomId = classroomId;
  // Inicializar valores dos filtros
  currentFrequencyModalParams.mainFilter = 'low_frequency_only';
  currentFrequencyModalParams.selectedClassifications = ['Abaixo do Mínimo', 'Crítico'];

  // mostra modal
  modal.style.display = "flex";

  // mostra loading
  document.getElementById("frequencyReportModalBody").innerHTML = "<p>Carregando...</p>";

  // busca conteúdo via fetch (por padrão: Abaixo do Mínimo e Crítico, filtro principal: low_frequency_only)
  const defaultClassifications = ['Abaixo do Mínimo', 'Crítico'];
  const params = new URLSearchParams({
    unity_id: unityId,
    main_filter: 'low_frequency_only'
  });
  if (classroomId && classroomId != 0) {
    params.append('classroom_id', classroomId);
  }
  defaultClassifications.forEach(c => params.append('risk_classifications[]', c));
  
  const url = '/pedagogical_trackings/frequency_report_modal?' + params.toString();
  
  fetch(url)
    .then(response => {
      if (!response.ok) {
        return response.text().then(text => {
          throw new Error(text || 'Erro ao carregar relatório');
        });
      }
      return response.text();
    })
    .then(html => {
      document.getElementById("frequencyReportModalBody").innerHTML = html;
      // Anexar event listeners após o HTML ser carregado (com pequeno delay para garantir que o DOM está pronto)
      setTimeout(function() {
        attachFilterListeners();
      }, 50);
    })
    .catch(err => {
      console.error("Erro ao carregar modal:", err);
      document.getElementById("frequencyReportModalBody").innerHTML =
        '<p style="color:red;">Erro ao carregar o relatório de Alunos Faltosos: ' + err.message + '</p>';
    });
}

// Função para anexar event listeners aos filtros
function attachFilterListeners() {
  // Usar event delegation no modal body para capturar eventos mesmo após recarregar
  const modalBody = document.getElementById("frequencyReportModalBody");
  if (!modalBody) {
    console.log('Modal body não encontrado');
    return;
  }

  // Remover listener anterior se existir
  if (modalBody._filterChangeHandler) {
    modalBody.removeEventListener('change', modalBody._filterChangeHandler);
    modalBody._filterChangeHandler = null;
  }

  // Criar handler para eventos de change
  modalBody._filterChangeHandler = function(e) {
    const target = e.target;
    
    // Verificar se o target é um elemento de filtro
    if (!target || (!target.matches('input[type="radio"][name="main_filter"]') && 
                    !target.matches('input[type="checkbox"][name="risk_classifications[]"]'))) {
      return;
    }
    
    // Se for um radio button do filtro principal
    if (target.type === 'radio' && target.name === 'main_filter') {
      e.stopPropagation();
      // Capturar valores do formulário antes de recarregar
      const form = document.getElementById("riskClassificationFilter");
      let selectedClassifications = currentFrequencyModalParams.selectedClassifications;
      
      if (form) {
        selectedClassifications = Array.from(form.querySelectorAll('input[name="risk_classifications[]"]:checked'))
          .map(cb => cb.value);
        if (selectedClassifications.length === 0) {
          selectedClassifications = ['Abaixo do Mínimo', 'Crítico'];
        }
      }
      
      // Atualizar valores globais
      currentFrequencyModalParams.mainFilter = target.value;
      currentFrequencyModalParams.selectedClassifications = selectedClassifications;
      
      // Chamar applyRiskFilter com os valores capturados
      applyRiskFilterWithValues(target.value, selectedClassifications);
      return;
    }
    
    // Se for um checkbox de classificação de risco
    if (target.type === 'checkbox' && target.name === 'risk_classifications[]') {
      e.stopPropagation();
      
      // Capturar o estado atual do checkbox
      const checkboxValue = target.value;
      const isNowChecked = target.checked;
            
      // Usar o filtro principal atual armazenado globalmente
      let mainFilter = currentFrequencyModalParams.mainFilter || 'low_frequency_only';
      
      // Processar a mudança imediatamente, buscando checkboxes do modalBody
      const processCheckboxChange = function() {
        const modalBody = document.getElementById("frequencyReportModalBody");
        let selectedClassifications = [];
        
        // Buscar checkboxes diretamente do modalBody
        if (modalBody) {
          selectedClassifications = Array.from(modalBody.querySelectorAll('input[name="risk_classifications[]"]:checked'))
            .map(cb => cb.value);
        }
        
        // Se não encontrar checkboxes marcados, calcular baseado no estado atual
        if (selectedClassifications.length === 0) {
          // Usar valores globais e atualizar com base no checkbox que foi clicado
          var globalClassifications = currentFrequencyModalParams.selectedClassifications || ['Abaixo do Mínimo', 'Crítico'];
          selectedClassifications = globalClassifications.slice(); // Criar cópia do array
          
          // Atualizar baseado no checkbox que foi clicado
          if (isNowChecked) {
            // Adicionar se não estiver na lista
            if (selectedClassifications.indexOf(checkboxValue) === -1) {
              selectedClassifications.push(checkboxValue);
            }
          } else {
            // Remover se estiver na lista
            var index = selectedClassifications.indexOf(checkboxValue);
            if (index !== -1) {
              selectedClassifications.splice(index, 1);
            }
          }
        }
        
        // Tentar buscar o formulário para obter o filtro principal
        let form = document.getElementById("riskClassificationFilter");
        if (!form && modalBody) {
          form = modalBody.querySelector("#riskClassificationFilter");
        }
        
        if (form) {
          // Obter valor do radio button do filtro principal
          const checkedRadio = form.querySelector('input[name="main_filter"]:checked');
          if (checkedRadio && checkedRadio.value) {
            mainFilter = checkedRadio.value;
            currentFrequencyModalParams.mainFilter = mainFilter;
          }
        }
                
        if (selectedClassifications.length === 0) {
          // Reverter mudança
          target.checked = !isNowChecked;
          alert('Selecione pelo menos uma classificação de risco.');
          return;
        }
        
        // Atualizar valores globais
        currentFrequencyModalParams.selectedClassifications = selectedClassifications;
        
        // Aplicar filtro com valores capturados
        applyRiskFilterWithValues(mainFilter, selectedClassifications);
      };
      
      // Aguardar um pouco para garantir que o estado do checkbox foi atualizado no DOM
      setTimeout(processCheckboxChange, 100);
    }
  };

  // Adicionar listener usando event delegation no modal body
  modalBody.addEventListener('change', modalBody._filterChangeHandler);
  
}

// Função auxiliar para aplicar filtro com valores específicos
function applyRiskFilterWithValues(mainFilter, selectedClassifications) {
  
  const modal = document.getElementById("frequencyReportModal");
  if (!modal || modal.style.display === 'none') {
    console.log('Modal não está visível');
    return;
  }

  const modalBody = document.getElementById("frequencyReportModalBody");
  
  // Garantir valores padrão
  mainFilter = mainFilter || currentFrequencyModalParams.mainFilter || 'low_frequency_only';
  selectedClassifications = selectedClassifications || currentFrequencyModalParams.selectedClassifications || ['Abaixo do Mínimo', 'Crítico'];
  
  if (selectedClassifications.length === 0) {
    selectedClassifications = ['Abaixo do Mínimo', 'Crítico'];
  }
  
  // Atualizar valores globais
  currentFrequencyModalParams.mainFilter = mainFilter;
  currentFrequencyModalParams.selectedClassifications = selectedClassifications;

  // Mostrar loading
  modalBody.innerHTML = "<p>Carregando...</p>";

  // Usar parâmetros armazenados
  const unityId = currentFrequencyModalParams.unityId;
  const classroomId = currentFrequencyModalParams.classroomId;

  if (!unityId) {
    console.error('Unity ID não encontrado');
    return;
  }

  // Construir URL com filtros
  const params = new URLSearchParams({
    unity_id: unityId,
    main_filter: mainFilter
  });
  if (classroomId && classroomId != 0) {
    params.append('classroom_id', classroomId);
  }
  selectedClassifications.forEach(c => params.append('risk_classifications[]', c));

  const url = '/pedagogical_trackings/frequency_report_modal?' + params.toString();

  fetch(url)
    .then(response => {
      if (!response.ok) {
        return response.text().then(text => {
          throw new Error(text || 'Erro ao carregar relatório');
        });
      }
      return response.text();
    })
    .then(html => {
      modalBody.innerHTML = html;
      // Anexar event listeners após o HTML ser carregado (com pequeno delay para garantir que o DOM está pronto)
      setTimeout(function() {
        attachFilterListeners();
      }, 50);
    })
    .catch(err => {
      console.error("Erro ao aplicar filtro:", err);
      modalBody.innerHTML =
        '<p style="color:red;">Erro ao aplicar filtro: ' + err.message + '</p>';
    });
}

// Tornar a função global para ser acessível de qualquer lugar
window.applyRiskFilter = function() {
  console.log('applyRiskFilter chamada');
  const modal = document.getElementById("frequencyReportModal");
  if (!modal || modal.style.display === 'none') {
    console.log('Modal não está visível');
    return;
  }

  const modalBody = document.getElementById("frequencyReportModalBody");
  
  // Tentar buscar o formulário, se não encontrar, usar valores padrão
  let form = document.getElementById("riskClassificationFilter");
  let selectedClassifications = [];
  let mainFilter = 'low_frequency_only';
  
  if (form) {
    // Obter valores dos checkboxes de classificação selecionados
    selectedClassifications = Array.from(form.querySelectorAll('input[name="risk_classifications[]"]:checked'))
      .map(cb => cb.value);

    // Obter valor do radio button do filtro principal
    const checkedRadio = form.querySelector('input[name="main_filter"]:checked');
    mainFilter = (checkedRadio && checkedRadio.value) ? checkedRadio.value : 'low_frequency_only';
  } else {
    console.warn('Formulário não encontrado, usando valores padrão');
    // Usar valores padrão se o formulário não estiver disponível
    selectedClassifications = ['Abaixo do Mínimo', 'Crítico'];
    mainFilter = 'low_frequency_only';
  }

  // Se nenhum checkbox de classificação estiver selecionado, usar padrão
  if (selectedClassifications.length === 0) {
    selectedClassifications = ['Abaixo do Mínimo', 'Crítico'];
  }
  
  // Chamar função auxiliar com os valores
  applyRiskFilterWithValues(mainFilter, selectedClassifications);
};

function closeFrequencyReportModal(event) {
  if (event) event.preventDefault();

  const modal = document.getElementById("frequencyReportModal");
  if (!modal) return;
  
  const modalBody = document.getElementById("frequencyReportModalBody");
  if (modalBody && modalBody._filterChangeHandler) {
    modalBody.removeEventListener('change', modalBody._filterChangeHandler);
    modalBody._filterChangeHandler = null;
  }
  
  modal.style.display = "none";
  modalBody.innerHTML = "";
}

function openClassCouncilModal(unityId, classroomId) {
  const modal = document.getElementById("classCouncilModal");
  if (!modal) return;

  modal.style.display = "flex";
  document.getElementById("classCouncilModalBody").innerHTML = "<p>Carregando...</p>";

  const params = new URLSearchParams({ unity_id: unityId });
  if (classroomId && classroomId != 0) {
    params.append('classroom_id', classroomId);
  }

  fetch('/pedagogical_trackings/class_council_modal?' + params.toString())
    .then(response => {
      if (!response.ok) {
        return response.text().then(text => {
          throw new Error(text || 'Erro ao carregar modal');
        });
      }
      return response.text();
    })
    .then(html => {
      document.getElementById("classCouncilModalBody").innerHTML = html;
    })
    .catch(err => {
      console.error("Erro ao carregar modal do conselho de classe:", err);
      document.getElementById("classCouncilModalBody").innerHTML =
        '<p style="color:red;">Erro ao carregar o Conselho de Classe: ' + err.message + '</p>';
    });
}

function closeClassCouncilModal(event) {
  if (event) event.preventDefault();

  const modal = document.getElementById("classCouncilModal");
  if (!modal) return;

  modal.style.display = "none";
  document.getElementById("classCouncilModalBody").innerHTML = "";
}

function openTagCloudModal(event) {
  if (event) event.preventDefault();

  var gradeId = $('#tag_cloud_grade_id').val();
  var disciplineId = $('#tag_cloud_discipline_id').val();

  if (!gradeId || gradeId === 'empty' || !disciplineId || disciplineId === 'empty') {
    alert('Selecione uma série e uma disciplina para analisar.');
    return false;
  }

  var unityId = $('#tag_cloud_unity_id').val();
  var stepNumber = $('#tag_cloud_step_number').val();
  var modal = document.getElementById('tagCloudModal');
  var body = document.getElementById('tagCloudModalBody');
  var summary = document.getElementById('tagCloudModalSummary');

  if (!modal) return false;

  modal.style.display = 'flex';
  summary.textContent = '';
  body.innerHTML = '<p class="pedagogical-modal__loading">Carregando análise...</p>';

  var params = new URLSearchParams({
    grade_id: gradeId,
    discipline_id: disciplineId
  });

  if (unityId && unityId !== 'empty') {
    params.append('unity_id', unityId);
  }

  if (stepNumber && stepNumber !== 'empty') {
    params.append('step_number', stepNumber);
  }

  fetch('/pedagogical_trackings/tag_cloud_modal?' + params.toString())
    .then(function(response) {
      if (!response.ok) {
        return response.text().then(function(text) {
          throw new Error(text || 'Erro ao carregar análise');
        });
      }
      return response.text();
    })
    .then(function(html) {
      body.innerHTML = html;
      var summaryData = document.getElementById('tag-cloud-summary-data');
      if (summaryData) {
        summary.textContent = summaryData.getAttribute('data-summary') || '';
      }
    })
    .catch(function(err) {
      console.error('Erro ao carregar tag cloud:', err);
      body.innerHTML = '<p style="color:#b91c1c;">Erro ao carregar a análise: ' + err.message + '</p>';
    });

  return false;
}

function closeTagCloudModal(event) {
  if (event) event.preventDefault();

  var modal = document.getElementById('tagCloudModal');
  if (!modal) return;

  modal.style.display = 'none';
  document.getElementById('tagCloudModalBody').innerHTML = '';
  document.getElementById('tagCloudModalSummary').textContent = '';
}

function isPedagogicalModalOpen(modal) {
  return modal && modal.style.display === 'flex';
}

function closeActivePedagogicalModal(event) {
  if (isPedagogicalModalOpen(document.getElementById('resumeModal'))) {
    closeResumeModal(event);
    return true;
  }

  if (isPedagogicalModalOpen(document.getElementById('frequencyReportModal'))) {
    closeFrequencyReportModal(event);
    return true;
  }

  if (isPedagogicalModalOpen(document.getElementById('classCouncilModal'))) {
    closeClassCouncilModal(event);
    return true;
  }

  if (isPedagogicalModalOpen(document.getElementById('tagCloudModal'))) {
    closeTagCloudModal(event);
    return true;
  }

  return false;
}

$(document).ready(function() {
  $('#tag-cloud-form').on('submit', openTagCloudModal);
  $('#tag_cloud_grade_id').on('change', onTagCloudGradeChange);
  resetTagCloudDependentFilters();

  $('a[href="#pedagogical-content-analysis"][data-toggle="tab"]').on('shown.bs.tab', function() {
    $('#pedagogical-content-analysis').find('input.select2, select.select2').each(function() {
      var $field = $(this);
      if ($field.data('select2')) {
        $field.select2('val', $field.val());
      }
    });
  });

  $(document).on('click', '.pedagogical-modal', function(event) {
    if (event.target !== this) return;
    closeActivePedagogicalModal(event);
  });

  $(document).on('keydown', function(event) {
    if (event.key !== 'Escape' && event.keyCode !== 27) return;
    if (closeActivePedagogicalModal(event)) {
      event.preventDefault();
    }
  });
});

function onTagCloudGradeChange(event) {
  clear_empty(event);

  var gradeId = $('#tag_cloud_grade_id').val();
  resetTagCloudDependentFilters();

  if (!gradeId || gradeId === 'empty') {
    return;
  }

  fetch('/pedagogical_trackings/tag_cloud_filters?grade_id=' + encodeURIComponent(gradeId))
    .then(function(response) {
      if (!response.ok) {
        throw new Error('Erro ao carregar filtros');
      }
      return response.json();
    })
    .then(function(data) {
      setTagCloudSelectOptions('#tag_cloud_discipline_id', data.disciplines || []);
      setTagCloudSelectOptions('#tag_cloud_unity_id', data.unities || []);
    })
    .catch(function(err) {
      console.error('Erro ao carregar filtros da tag cloud:', err);
      alert('Ocorreu um erro ao carregar disciplinas e escolas da série selecionada.');
    });
}

function resetTagCloudDependentFilters() {
  setTagCloudSelectOptions('#tag_cloud_discipline_id', []);
  setTagCloudSelectOptions('#tag_cloud_unity_id', []);
}

function setTagCloudSelectOptions(selector, items) {
  var $field = $(selector);
  var options = [{ id: 'empty', name: '<option></option>', text: '' }].concat(
    (items || []).map(function(item) {
      return {
        id: item.id,
        name: item.name || item.text,
        text: item.text || item.name
      };
    })
  );

  $field.prop('disabled', items.length === 0);
  $field.select2('val', '');
  $field.select2({ data: options, width: '100%' });
}

