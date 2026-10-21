$(function () {
  'use strict';

  var $formElement = $('#knowledge_area_teaching_plan');
  if ($formElement.length && typeof UnsavedChangesGuard !== 'undefined') {
    UnsavedChangesGuard.watch($formElement, {
      title: 'Deseja salvar este plano de ensino antes de sair?',
      message: 'Você fez alterações no plano de ensino que ainda não foram salvas. ' +
               'Se sair agora, suas alterações serão perdidas.'
    });
  }
});
