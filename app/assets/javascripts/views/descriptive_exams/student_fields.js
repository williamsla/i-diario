$(function () {
  var $formElement = $('form[id^="edit_descriptive_exam"]');
  if ($formElement.length && typeof UnsavedChangesGuard !== 'undefined') {
    UnsavedChangesGuard.watch($formElement, {
      title: 'Deseja salvar este parecer descritivo antes de sair?',
      message: 'Você fez alterações no parecer descritivo que ainda não foram salvas. ' +
               'Se sair agora, suas alterações serão perdidas.'
    });
  }

  // Seleciona os textareas com o atributo readonly
  $("textarea[readonly]").each(function () {
    createSummerNote(this, {
      toolbar: [
        ['font', ['bold', 'italic', 'underline', 'clear']],
      ],
      disabled: true
    });
  });

  $('textarea[maxLength]').maxlength();

  createSummerNote("textarea[id^=descriptive_exam_students_attributes_]", {
    toolbar: [
      ['font', ['bold', 'italic', 'underline', 'clear']],
    ]
  });
});
