function experienceFieldBadgeClass(experienceFields) {
  if (!experienceFields) return '';

  var sum = 0;
  for (var i = 0; i < experienceFields.length; i++) {
    sum += experienceFields.charCodeAt(i);
  }

  return 'experience-field-badge experience-field-badge--color-' + (sum % 5);
}

function initializeListEvents() {
  // Settings
  var $widget = $(this),
      $checkbox = $(this).find('input[type=checkbox]').first(),
      color = "info",
      style = "list-group-item-",
      settings = {
          on: {
              icon: 'fa fa-check'
          },
          off: {
              icon: 'margin-left-17px'
          }
      };

  $widget.css('cursor', 'pointer')

  // Event Handlers
  $widget.on('click', function () {
    $checkbox.prop('checked', !$checkbox.is(':checked'));
    $checkbox.triggerHandler('change');
    updateDisplay();
  });
  $checkbox.on('change', function () {
      updateDisplay();
  });


  // Actions
  function updateDisplay() {
      var isChecked = $checkbox.is(':checked');

      // Set the button's state
      $widget.data('state', (isChecked) ? "on" : "off");

      // Set the button's icon
      $widget.find('.state-icon')
          .removeClass()
          .addClass('state-icon ' + settings[$widget.data('state')].icon);

      // Update the button's color
      if (isChecked) {
          $widget.addClass(style + color + ' active');
      } else {
          $widget.removeClass(style + color + ' active');
      }
  }

  // Initialization
  function init() {

      if ($widget.data('checked') == true) {
          $checkbox.prop('checked', !$checkbox.is(':checked'));
      }

      updateDisplay();

      $widget.addClass('initialized');

      // Inject the icon if applicable
      if ($widget.find('.state-icon').length == 0) {
          $widget.prepend('<span class="state-icon ' + settings[$widget.data('state')].icon + '"></span>');
      }
  }
  init();
}

function hideContent(content) {
  content.find("input[type=checkbox]").prop('checked', false);
  content.remove();
}

function editContent(id) {
  var content = $('#' + id);
  var inputAddContent = $('.contents-select2-container .select2-input');
  inputAddContent.val(content.find("input[type=checkbox]").data('content_description'));
  inputAddContent.trigger('click');
  inputAddContent.focus();
  hideContent(content);
}

function removeContent(id) {
  var content = $('#' + id);
  hideContent(content);
}

function editObjective(id) {
  var objective = $('#' + id);
  var inputAddObjective = $('.objectives-select2-container .select2-input');
  inputAddObjective.val(objective.find("input[type=checkbox]").data('objective_description'));
  inputAddObjective.trigger('click');
  inputAddObjective.focus();
  hideContent(objective);
}

function removeObjective(id) {
  var objective = $('#' + id);
  hideContent(objective);
}

$(function () {
  $('.list-group.checked-list-box .list-group-item').each(initializeListEvents);

  window.Select2.class.multi.prototype.clearSearch=function(){
      var placeholder = this.getPlaceholder(),
          maxWidth = this.getMaxSearchWidth();

      if (placeholder !== undefined  && this.getVal().length === 0 &&  this.search.val()=="") {
        this.search.val(placeholder).addClass("select2-default");
        this.search.width(maxWidth > 0 ? maxWidth : this.container.css("width"));
      }
  }
});

// carregando modal de estilo tabela
document.addEventListener('DOMContentLoaded', () => {
  const addRowBtn = document.getElementById('add-new-row');
  const confirmBtn = document.getElementById('confirm-add-contents');
  const tableBody = document.querySelector('#modal-table tbody');

  if (addRowBtn) {
    addRowBtn.addEventListener('click', () => {
      const newRow = tableBody.rows[0].cloneNode(true);
      Array.from(newRow.querySelectorAll('input')).forEach(input => input.value = '');
      tableBody.appendChild(newRow);
    });
  }

  if (tableBody) {
    tableBody.addEventListener('click', e => {
      if (e.target.classList.contains('remove-row')) {
        if (tableBody.rows.length > 1) {
          e.target.closest('tr').remove();
        }
      }
    });
  }

  if (confirmBtn) {
    confirmBtn.addEventListener('click', () => {
      const rows = tableBody.querySelectorAll('tr');
    
      rows.forEach(row => {
        const content = row.querySelector('input[name="content[]"]').value.trim();
        const objective = row.querySelector('input[name="objective[]"]').value.trim();
        const methodology = row.querySelector('input[name="methodology[]"]').value.trim();
        const evaluation = row.querySelector('input[name="evaluation[]"]').value.trim();
        const references = row.querySelector('input[name="references[]"]').value.trim();
    
        if (!content) return;
    
        const addItem = (ulId, fieldName, value) => {
          const id = `new-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
          const listItem = document.createElement('li');
          listItem.className = 'list-group-item manual';
          listItem.id = `${ulId}_${id}`;
          listItem.innerHTML = `
            <input type="hidden" name="knowledge_area_teaching_plan[teaching_plan_attributes][${fieldName}_tags][]" value="${value}">
            ${value}
          `;
          document.getElementById(`${ulId}-list`).appendChild(listItem);
        };
    
        addItem('contents', 'contents', content);
        if (objective) addItem('objectives', 'objectives', objective);
        if (methodology) addItem('methodologies', 'methodologies', methodology);
        if (evaluation) addItem('evaluations', 'evaluations', evaluation);
        if (references) addItem('references', 'references', references);
      });
    
      $('#addContentsByTableModal').modal('hide');
    });
    
  }
});
