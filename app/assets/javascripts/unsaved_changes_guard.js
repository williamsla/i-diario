/**
 * UnsavedChangesGuard - Módulo reutilizável para detectar alterações não salvas
 *
 * Uso:
 *   UnsavedChangesGuard.watch('#meu-form');
 *
 *   // Com opções personalizadas:
 *   UnsavedChangesGuard.watch('#meu-form', {
 *     title: 'Título personalizado',
 *     message: 'Mensagem personalizada',
 *     ignoreSelectors: ['.filtro', '.select2-search-field input']
 *   });
 *
 * O módulo:
 * - Detecta mudanças em inputs, selects, textareas, checkboxes, radio buttons
 * - Intercepta cliques em links e botões de navegação
 * - Mostra modal bootbox se houver alterações não salvas
 * - Exibe alerta nativo do navegador ao tentar fechar a aba
 * - Reseta o estado quando o form é submetido com sucesso
 */
(function (global) {
  'use strict';

  var UnsavedChangesGuard = {
    instances: [],

    defaultOptions: {
      title: 'Deseja salvar este lançamento antes de sair?',
      message: 'Você fez alterações que ainda não foram salvas. ' +
               'Se sair agora, suas alterações serão perdidas.',
      confirmLabel: 'Salvar',
      cancelLabel: 'Sair sem salvar',
      confirmClass: 'btn new-save-style',
      cancelClass: 'btn new-delete-style',
      ignoreSelectors: [
        '.select2-search-field input',
        '.select2-input',
        '.no-unsaved-guard',
        '[data-no-unsaved-guard]'
      ],
      submitButtonSelector: 'input[type=submit], button[type=submit]',
      navigationSelectors: 'a:not(.no-confirm):not([href^="#"]):not([target="_blank"]), button:not(.no-confirm):not([type=submit])'
    },

    /**
     * Inicia a observação de um formulário
     * @param {string|jQuery} formSelector - Seletor ou elemento jQuery do formulário
     * @param {Object} options - Opções personalizadas (opcional)
     * @returns {Object} Instância do guard para controle manual
     */
    watch: function (formSelector, options) {
      var $form = $(formSelector);

      if (!$form.length) {
        console.warn('UnsavedChangesGuard: Formulário não encontrado:', formSelector);
        return null;
      }

      var opts = $.extend({}, this.defaultOptions, options || {});
      var instance = this._createInstance($form, opts);

      this.instances.push(instance);
      return instance;
    },

    _createInstance: function ($form, opts) {
      var self = this;
      var hasUnsavedChanges = false;
      var isSubmitting = false;
      var initialValues = {};
      var formId = $form.attr('id') || 'form_' + Date.now();

      // Rails/simple_form envia um hidden (valor desmarcado) e um checkbox com o mesmo name.
      // Guardar os dois na mesma chave faz o hidden "0" divergir do boolean do checkbox
      // e o formulário parece alterado mesmo sem edição do usuário.
      var checkboxNames = function () {
        var names = {};
        $form.find('input[type="checkbox"]').each(function () {
          if (this.name) {
            names[this.name] = true;
          }
        });
        return names;
      };

      var isRailsCheckboxHidden = function ($el, names) {
        var name = $el.attr('name');
        return $el.is('input[type="hidden"]') && !!name && !!names[name];
      };

      var fieldName = function ($el, names) {
        var name = $el.attr('name') || $el.attr('id');

        if (!name || self._shouldIgnore($el, opts) || isRailsCheckboxHidden($el, names)) {
          return null;
        }

        return name;
      };

      var fieldValue = function ($el) {
        if ($el.is(':checkbox') || $el.is(':radio')) {
          return $el.is(':checked');
        }

        return $el.val();
      };

      var captureInitialValues = function () {
        var names = checkboxNames();
        initialValues = {};
        $form.find('input, select, textarea').each(function () {
          var $el = $(this);
          var name = fieldName($el, names);

          if (!name) {
            return;
          }

          initialValues[name] = fieldValue($el);
        });
      };

      var checkForChanges = function () {
        var names = checkboxNames();
        var changed = false;

        $form.find('input, select, textarea').each(function () {
          var $el = $(this);
          var name = fieldName($el, names);

          if (!name) {
            return;
          }

          if (initialValues.hasOwnProperty(name) && initialValues[name] !== fieldValue($el)) {
            changed = true;
            return false;
          }
        });

        return changed;
      };

      var markAsChanged = function () {
        hasUnsavedChanges = true;
      };

      var markAsSaved = function () {
        hasUnsavedChanges = false;
        captureInitialValues();
      };

      var shouldBlockNavigation = function () {
        return hasUnsavedChanges || checkForChanges();
      };

      var showConfirmationModal = function (onConfirm, onCancel) {
        bootbox.confirm({
          title: opts.title,
          message: opts.message,
          buttons: {
            confirm: { label: opts.confirmLabel, className: opts.confirmClass },
            cancel: { label: opts.cancelLabel, className: opts.cancelClass }
          },
          callback: function (result) {
            if (result) {
              onConfirm();
            } else {
              onCancel();
            }
          }
        });
      };

      var handleNavigation = function (e) {
        if (isSubmitting || !shouldBlockNavigation()) {
          return true;
        }

        e.preventDefault();
        e.stopPropagation();

        var target = e.currentTarget;

        showConfirmationModal(
          function () {
            var $submitBtn = $form.find(opts.submitButtonSelector).first();
            if ($submitBtn.length) {
              isSubmitting = true;
              $submitBtn.click();
            }
          },
          function () {
            hasUnsavedChanges = false;
            isSubmitting = true;

            if (target.tagName === 'A' && target.href) {
              window.location.href = target.href;
            } else {
              $(target).off('click.unsavedGuard').click();
            }
          }
        );

        return false;
      };

      var handleBeforeUnload = function (e) {
        if (isSubmitting || !shouldBlockNavigation()) {
          return undefined;
        }

        var message = opts.message;
        e.returnValue = message;
        return message;
      };

      var bindEvents = function () {
        var ignoreSelector = opts.ignoreSelectors.join(', ');

        $form.on('change.unsavedGuard input.unsavedGuard', 'input, select, textarea', function (e) {
          var $el = $(e.target);
          if (!self._shouldIgnore($el, opts) && !isRailsCheckboxHidden($el, checkboxNames())) {
            markAsChanged();
          }
        });

        $form.on('summernote.change', function () {
          markAsChanged();
        });

        $form.on('cocoon:after-insert cocoon:after-remove', function () {
          markAsChanged();
        });

        $form.on('submit.unsavedGuard', function () {
          isSubmitting = true;
          hasUnsavedChanges = false;
        });

        $(document).on('click.unsavedGuard_' + formId, opts.navigationSelectors, handleNavigation);

        $(window).on('beforeunload.unsavedGuard_' + formId, handleBeforeUnload);
      };

      var unbindEvents = function () {
        $form.off('.unsavedGuard');
        $(document).off('.unsavedGuard_' + formId);
        $(window).off('.unsavedGuard_' + formId);
      };

      captureInitialValues();
      bindEvents();

      return {
        formId: formId,
        markAsChanged: markAsChanged,
        markAsSaved: markAsSaved,
        hasChanges: shouldBlockNavigation,
        reset: function () {
          hasUnsavedChanges = false;
          captureInitialValues();
        },
        destroy: function () {
          unbindEvents();
          var idx = self.instances.indexOf(this);
          if (idx > -1) {
            self.instances.splice(idx, 1);
          }
        },
        setSubmitting: function (value) {
          isSubmitting = !!value;
        }
      };
    },

    _shouldIgnore: function ($el, opts) {
      for (var i = 0; i < opts.ignoreSelectors.length; i++) {
        if ($el.is(opts.ignoreSelectors[i])) {
          return true;
        }
      }
      return false;
    },

    destroyAll: function () {
      while (this.instances.length) {
        this.instances[0].destroy();
      }
    }
  };

  global.UnsavedChangesGuard = UnsavedChangesGuard;
})(window);
