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
  $('.fa-pie-chart').closest('h2').after(`<img src="${img_src}" class="beta-badge" style="margin-bottom: 9px; margin-left: 5px" title="${beta_title}">`);
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

  // mostra modal
  modal.style.display = "flex";

  // atualiza botão de download
  const downloadBtn = document.getElementById("downloadXlsxBtn");
  downloadBtn.onclick = () => {
    const url = `/pedagogical_trackings/resume_xlsx?unity_id=${unityId}&classroom_id=${classroomId || 0}`;
    window.location.href = url; // força download
  }

  // busca conteúdo via fetch
  fetch(`/pedagogical_trackings/resume_modal?unity_id=${unityId}&classroom_id=${classroomId || 0}`)
    .then(response => response.text())
    .then(html => {
      document.getElementById("resumeModalBody").innerHTML = html;
    })
    .catch(err => {
      console.error("Erro ao carregar modal:", err);
      document.getElementById("resumeModalBody").innerHTML =
        "<p style='color:red;'>Erro ao carregar o resumo.</p>";
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
  mainFilter: 'absences_only',
  selectedClassifications: ['Abaixo do Mínimo', 'Crítico']
};

function openFrequencyReportModal(unityId, classroomId) {
  const modal = document.getElementById("frequencyReportModal");
  if (!modal) return;

  // Armazenar parâmetros para uso no filtro
  currentFrequencyModalParams.unityId = unityId;
  currentFrequencyModalParams.classroomId = classroomId;
  // Inicializar valores dos filtros
  currentFrequencyModalParams.mainFilter = 'absences_only';
  currentFrequencyModalParams.selectedClassifications = ['Abaixo do Mínimo', 'Crítico'];

  // mostra modal
  modal.style.display = "flex";

  // mostra loading
  document.getElementById("frequencyReportModalBody").innerHTML = "<p>Carregando...</p>";

  // busca conteúdo via fetch (por padrão: Abaixo do Mínimo e Crítico, filtro principal: absences_only)
  const defaultClassifications = ['Abaixo do Mínimo', 'Crítico'];
  const params = new URLSearchParams({
    unity_id: unityId,
    main_filter: 'absences_only'
  });
  if (classroomId && classroomId != 0) {
    params.append('classroom_id', classroomId);
  }
  defaultClassifications.forEach(c => params.append('risk_classifications[]', c));
  
  const url = `/pedagogical_trackings/frequency_report_modal?${params.toString()}`;
  
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
        `<p style='color:red;'>Erro ao carregar o relatório de Alunos Faltosos: ${err.message}</p>`;
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
      let mainFilter = currentFrequencyModalParams.mainFilter || 'absences_only';
      
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
          const formMainFilter = form.querySelector('input[name="main_filter"]:checked')?.value;
          if (formMainFilter) {
            mainFilter = formMainFilter;
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
  mainFilter = mainFilter || currentFrequencyModalParams.mainFilter || 'absences_only';
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

  const url = `/pedagogical_trackings/frequency_report_modal?${params.toString()}`;

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
        `<p style='color:red;'>Erro ao aplicar filtro: ${err.message}</p>`;
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
  let mainFilter = 'absences_only';
  
  if (form) {
    // Obter valores dos checkboxes de classificação selecionados
    selectedClassifications = Array.from(form.querySelectorAll('input[name="risk_classifications[]"]:checked'))
      .map(cb => cb.value);

    // Obter valor do radio button do filtro principal
    mainFilter = form.querySelector('input[name="main_filter"]:checked')?.value || 'absences_only';
  } else {
    console.warn('Formulário não encontrado, usando valores padrão');
    // Usar valores padrão se o formulário não estiver disponível
    selectedClassifications = ['Abaixo do Mínimo', 'Crítico'];
    mainFilter = 'absences_only';
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
