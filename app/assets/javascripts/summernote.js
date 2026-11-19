function createSummerNote(element, options = {}) {
  $(element).summernote({
    lang: 'pt-BR',
    toolbar: options.toolbar || [],
    disableDragAndDrop : true,
    callbacks : {
      onInit : function () {
        bindPasteFromTopicsAndTables(this);
      },
      onPaste : function (event) {
        var thisNote = $(this);

        if (thisNote.data('skipPasteClean')) {
          thisNote.removeData('skipPasteClean');
          return;
        }

        var updatePastedText = function(someNote){
          var original = someNote.summernote('code');
          var cleaned = CleanPastedHTML(original);

          someNote.summernote('code', cleaned);
        };

        setTimeout(function () {
          updatePastedText(thisNote);
        }, 10);
      }
    }
  });

  if (options.disabled) {
    $(element).each(function(index, el) {
      $(el).summernote('disable');
    })
  }
}

// Word, Excel e páginas com tópicos/tabelas colocam uma imagem junto do texto
// na área de transferência. O Summernote trata isso como colagem de imagem e
// descarta o texto. Nesses casos o texto é inserido no cursor, como no PEI.
function bindPasteFromTopicsAndTables(textarea) {
  var editable = $(textarea).next('.note-editor').find('.note-editable').get(0);

  if (!editable || editable.getAttribute('data-plain-structure-paste')) {
    return;
  }

  editable.setAttribute('data-plain-structure-paste', '1');

  editable.addEventListener('paste', function (event) {
    var clipboard = event.clipboardData || window.clipboardData;

    if (!clipboard || !clipboardHasImageFile(clipboard)) {
      return;
    }

    var text = clipboardText(clipboard);
    var html = clipboardHtml(clipboard);

    if (!text.trim() && !html.trim()) {
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();
    $(textarea).data('skipPasteClean', true);

    var cleaned = text.trim() ? htmlFromPlainText(text) : CleanPastedHTML(html);

    window.setTimeout(function () {
      $(textarea).removeData('skipPasteClean');
      editable.focus();
      document.execCommand('insertHTML', false, cleaned);
      $(textarea).val(editable.innerHTML);
    }, 0);
  }, true);
}

function clipboardText(clipboard) {
  try {
    return clipboard.getData('text/plain') || clipboard.getData('Text') || '';
  } catch (error) {
    return '';
  }
}

function clipboardHtml(clipboard) {
  try {
    return clipboard.getData('text/html') || '';
  } catch (error) {
    return '';
  }
}

function clipboardHasImageFile(clipboard) {
  if (!clipboard.items) {
    return false;
  }

  for (var i = 0; i < clipboard.items.length; i++) {
    var item = clipboard.items[i];

    if (item.kind === 'file' && item.type && item.type.indexOf('image/') === 0) {
      return true;
    }
  }

  return false;
}

function htmlFromPlainText(text) {
  return $('<div>').text(text).html().replace(/\r\n|\r|\n/g, '<br>');
}

function CleanPastedHTML(input) {
  var commentStripper = new RegExp('<!--[\\s\\S]*?-->', 'g');
  var output = String(input || '').replace(commentStripper, '');
  var container = document.createElement('div');

  container.innerHTML = output;

  var dropTags = { SCRIPT: true, STYLE: true, META: true, LINK: true, TITLE: true };
  var keepTags = { DIV: true, P: true, B: true, I: true, U: true, BR: true };
  var nodes = Array.prototype.slice.call(container.querySelectorAll('*')).reverse();

  nodes.forEach(function (el) {
    var tag = el.tagName;
    var parent = el.parentNode;

    if (!parent) {
      return;
    }

    if (dropTags[tag]) {
      parent.removeChild(el);
      return;
    }

    while (el.attributes.length) {
      el.removeAttribute(el.attributes[0].name);
    }

    if (keepTags[tag]) {
      return;
    }

    if ((tag === 'TD' || tag === 'TH') && el.previousElementSibling) {
      parent.insertBefore(document.createTextNode(' '), el);
    }

    if (tag === 'LI' || tag === 'TR' || tag === 'H1' || tag === 'H2' || tag === 'H3' || tag === 'H4' || tag === 'H5' || tag === 'H6') {
      parent.insertBefore(document.createElement('br'), el);
    }

    while (el.firstChild) {
      parent.insertBefore(el.firstChild, el);
    }

    parent.removeChild(el);
  });

  return container.innerHTML;
}
