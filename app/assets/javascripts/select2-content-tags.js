$(function() {
  'use strict';

  // Impede que Enter no Select2 (conteúdos/habilidades) submeta o formulário
  $(document).on('keydown', 'form', function(e) {
    if ((e.which === 13 || e.keyCode === 13) && $(e.target).closest('.select2-container').length) {
      e.preventDefault();
      e.stopPropagation();
    }
  });

  const getObjectiveCode = (term) => {
    if (!term.length) {
      return;
    }

    const splitTerm = term.split(' ');
    if (splitTerm.length > 1) {
      return;
    }

    return splitTerm[0];
  };

  _.each($('.select2-content-tags-ajax'), function(element) {
    $(element).select2({
      tags: true,
      tokenSeparators: [],
      createSearchChoice: function (term,data) {

        if($(data).filter(function(k,obj){
          return obj.id.toLowerCase().localeCompare(term.toLowerCase()) == 0
        }).length == 0){
          return {
              id: $.trim(term),
              text: $.trim(term) + ' (Novo)'
          };
        }
      },
      minimumInputLength: 3,
      formatInputTooShort: function () {
          return "Digite no mínimo 3 caracteres";
      },
      ajax: {
        dataType: "json",
        url: $(element).data('url'),
        transport: function (params) {
          if (!params.data.filter.by_description && !params.data.merge_objectives_by_code) {
            params.success({ contents: []});
          } else {
            $.ajax(params);
          }
        },
        quietMillis: 500,
        data: function (term, page) {
          let query = {
            filter: {
              page: page,
              per: 10
            },
            merge_objectives_by_code: getObjectiveCode(term)
          }

          if ($(element).attr('data-filter-by-description')) {
            query.filter.by_description = term;
          }

          if ($(element).attr('data-filter-start-with-description')) {
            query.filter.start_with_description = term;
          }

          return query;
        },
        results: function (data, page) {
          page = page || 1;
          var results = [];
          // API de objectives retorna "objectives", outras podem retornar "contents"
          var items = (data && (data.contents || data.objectives)) ? (data.contents || data.objectives) : [];
          $.each(items, function(k, item){
            results.push({
              id: item.description,
              text: item.description
            })
          });

          return {
            results: results
          };
        }
      }
    }).select2('data', $(element).data('data'));
  });

  _.each($('.select2-tags'), function(element) {
    $(element).select2({
      tags: true,
      tokenSeparators: [],
      createSearchChoice: function (term, _data) {
        const type = $(element).data('content-type');

        return {
            id: $.trim(term),
            text: $.trim(term) + ' (Novo)'
        };
      },
      minimumInputLength: 3,
      formatInputTooShort: function () {
        return "Digite no mínimo 3 caracteres";
      },
      data: []
    });
  });
});
