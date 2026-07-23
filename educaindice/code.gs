var anoPreMatricula = 2026;

var planilha = SpreadsheetApp.openById("1CpR5w4B2wzCNC3n20pTQihGx3qet0M6f3ebKIhL6d1g");

var folhaInstituicao = planilha.getSheetByName("Instituição");
var folhaAlunos = planilha.getSheetByName("Alunos");
var folhaRespostas = planilha.getSheetByName("Respostas");

var folhaVagas = planilha.getSheetByName("Vagas");

var folhaProva = planilha.getSheetByName("Prova");
var folhaProvaQuestao = planilha.getSheetByName("ProvaQuestao");

var folhaHabilidades = planilha.getSheetByName("Habilidades");
var folhaConfiguracao = planilha.getSheetByName("Configuração");
var folhaQuantitativo = planilha.getSheetByName("Quantitativo");
var folhaCorrecao = planilha.getSheetByName("Correção");
var folhaCorrecaoConceitualNivel = planilha.getSheetByName("CorreçãoConceitualNivel");
var folhaCorrecaoPorHabilidade = planilha.getSheetByName("CorreçãoPorHabilidade");

var indexInstituicaoId = 0;
var indexInstituicaoNome = 1;
var indexInstituicaoLogoPrefeitura = 2;
var indexInstituicaoLogoSemed = 3;

var indexConfigEscola = 0;
var indexConfigAno = 1;
var indexConfigSeries = 2;
var indexConfigINEP = 3;
var indexConfigSenha = 4;

var indexProvaID = 0;
var indexProvaNome = 1;
var indexProvaLiberarFormulario = 2;
var indexProvaLiberarResultados = 3;
var indexProvaLiberarResultadosParaSEMED = 4;

var indexQuantitativo2Escola = 0;
var indexQuantitativo2Serie = 1;
var indexQuantitativo2Disciplina = 2;
var indexQuantitativo2QtdAlunos = 3;
var indexQuantitativo2QtdRespostasCompletas = 4;

var indexFolhaProvaQuestaoProvaRef = 0;
var indexFolhaProvaQuestaoSerie = 1;
var indexFolhaProvaQuestaoDisciplina = 2;
var indexFolhaProvaQuestaoTipo = 3;
var indexFolhaProvaQuestaoQuestao = 4;
var indexFolhaProvaQuestaoEnunciado = 5;
var indexFolhaProvaQuestaoAlternativa = 6;
var indexFolhaProvaQuestaoDescricao = 7;
var indexFolhaProvaQuestaoCorreta = 8;
var indexFolhaProvaQuestaoHabilidade = 9;
var indexFolhaProvaQuestaoQtdAlternativas = 10;
var indexFolhaProvaQuestaoSubQuestao = 11;
var indexFolhaProvaQuestaoSubDisciplina = 12;

var indexHabilidadesProvaRef = 0;
var indexHabilidadesSerie = 1;
var indexHabilidadesDisciplina = 2;
var indexHabilidadesCode = 3;
var indexHabilidadesDescricao = 4;

var indexAlunosEscola = 0;
var indexAlunosSerie = 1;
var indexAlunosTurma = 2;
var indexAlunosNome = 3;
var indexAlunosID = 4;
var indexAlunosProvaRef = 5;

var indexRespostasProvaRef = 0;
var indexRespostasEscola = 1;
var indexRespostasTurma = 2;
var indexRespostasIDAluno = 3;
var indexRespostasDisciplina = 4;
var indexRespostasSerie = 5;
var indexRespostasAtualizadoEm = 6;
var indexRespostasSincronizadoEm = 7;
var indexRespostasEscreveONome = 8;
var indexRespostasInicioGabarito = 9;

var indexCorrecaoProvaRef = 0;
var indexCorrecaoEscola = 1;
var indexCorrecaoSerie = 2;
var indexCorrecaoTurma = 3;
var indexCorrecaoIDAluno = 4;
var indexCorrecaoDisciplina = 5;
var indexCorrecaoEscreveONome = 6;
var indexCorrecaoAcertos = 7;
var indexCorrecaoErros= 8;
var indexCorrecaoCategoria = 9;
var indexCorrecaoSubDisciplina = 10;

var indexCorrecaoConceitualNivelProvaRef = 0;
var indexCorrecaoConceitualNivelEscola = 1;
var indexCorrecaoConceitualNivelSerie = 2;
var indexCorrecaoConceitualNivelTurma = 3;
var indexCorrecaoConceitualNivelIDAluno = 4;
var indexCorrecaoConceitualNivelDisciplina = 5;
var indexCorrecaoConceitualNivelCategoria = 6;

var indexCorrecaoPorHabilidadeProvaRef = 0;
var indexCorrecaoPorHabilidadeEscola = 1;
var indexCorrecaoPorHabilidadeSerie = 2;
var indexCorrecaoPorHabilidadeTurma = 3;
var indexCorrecaoPorHabilidadeIDAluno = 4;
var indexCorrecaoPorHabilidadeDisciplina = 5;
var indexCorrecaoPorHabilidadeHabilidade = 6;
var indexCorrecaoPorHabilidadeAcertos = 7;
var indexCorrecaoPorHabilidadeErros= 8;
var indexCorrecaoPorHabilidadeCategoria = 9;
var indexCorrecaoPorHabilidadeSubDisciplina = 10;



function include(filename) {
  return HtmlService.createHtmlOutputFromFile(filename)
      .getContent();
}

function getScriptUrl() {
 var url = ScriptApp.getService().getUrl();
 return url;
}

function doGet(e) {
  if (!e.parameter.page) {
    // When no specific page requested, return "home page"
    return HtmlService.createTemplateFromFile('index.html').evaluate();
  }
  // else, use page parameter to pick an html file from the script  
  var page = HtmlService.createTemplateFromFile(e.parameter['page']);
  page.inep = e.parameter['inep'];
  
  return page.evaluate();
}

function isNumeric(value) {
    return /^-?\d+$/.test(value);
}

function onlyUnique(value, index, array) {
  return array.indexOf(value) === index;
}

function ordenar(values) {
  return Array.from([...new Set(values)]).sort();
}


function login(inep_escola, senha) {
  
  const values = folhaConfiguracao.getRange('A1:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row) {
      return row[indexConfigINEP] == inep_escola
            && row[indexConfigSenha] == senha;
  });
    
  if (values.length > 0) {
    return {'status': true, 'message': 'Login realizado com sucesso.'};    
  } else {
    return {'status': false, 'message': 'INEP ou Senha inválidos.'};
  }
}

function submit(avaliacao, escola, turma, serie, aluno, disciplina, escrevenome, respostas) {
  let countRow = 1;
  let lastRowMatch = null;
  const values = folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow()).getValues().filter(function(row) {
        
        if (row[indexRespostasProvaRef] == avaliacao
                && row[indexRespostasDisciplina] == disciplina
                && row[indexRespostasIDAluno] == aluno) {
          
          lastRowMatch = lastRowMatch == null ? countRow : lastRowMatch;
          
          return true;
        }
        countRow = countRow + 1;
      }
    );

    let isUpdate = true;


    // salvando respostas do aluno
    if (lastRowMatch == null && values.length == 0) {
      isUpdate = false;
      folhaRespostas.appendRow([avaliacao,escola, turma, aluno, disciplina, serie, new Date(), ,escrevenome, ...respostas]);
      
    } else {
      isUpdate = true;

      folhaRespostas.getRange(`A${lastRowMatch}`).setValue(avaliacao);
      folhaRespostas.getRange(`B${lastRowMatch}`).setValue(escola);
      folhaRespostas.getRange(`C${lastRowMatch}`).setValue(turma);
      folhaRespostas.getRange(`D${lastRowMatch}`).setValue(aluno);
      folhaRespostas.getRange(`E${lastRowMatch}`).setValue(disciplina);
      folhaRespostas.getRange(`F${lastRowMatch}`).setValue(serie);
      folhaRespostas.getRange(`G${lastRowMatch}`).setValue(new Date());
      
      folhaRespostas.getRange(`I${lastRowMatch}`).setValue(escrevenome);
      var col = indexRespostasInicioGabarito + 1;
      for (var x =0; x < respostas.length; x++) {
        folhaRespostas.getRange(lastRowMatch, col).setValue(respostas[x]);
        col++;
      }
    } 

    return {'status': true, 'message': 'Gabarito salvo com sucesso'};
  
}

function getCabecalho() {
    const values = folhaInstituicao.getRange('A2:Z'+folhaInstituicao.getLastRow()).getValues().filter(function(row) {
        return row[indexInstituicaoId] == 1;
      }
    );

    return [
            values[0][indexInstituicaoNome].toString(), 
            values[0][indexInstituicaoLogoPrefeitura].toString(),
            values[0][indexInstituicaoLogoSemed].toString()
          ];
}

function getSeries() {
    const values = folhaConfiguracao.getRange('A1:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row) {
        return row[indexConfigAno] == anoPreMatricula;
      }
    ).reduce((acc, cur) => {
      return acc.concat(cur[indexConfigSeries].toString().split(';'));
    }, []);
    
    const series = Array.from([...new Set(values)]).sort();

    return series;
}

function getSeriesPorEscola(escola) {
    const values = folhaConfiguracao.getRange('A1:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row) {
        return row[indexConfigEscola] == escola;
      }
    ).reduce((acc, cur) => {
      return acc.concat(cur[indexConfigSeries].toString().split(';'));
    }, []);
    
    const series = Array.from([...new Set(values)]).sort();

    return series;
}

function getSeriesPorEscolaINEP(inep) {
    const values = folhaConfiguracao.getRange('A1:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row) {
        return row[indexConfigINEP] == inep;
      }
    ).reduce((acc, cur) => {
      return acc.concat(cur[indexConfigSeries].toString().split(';'));
    }, []);
    
    const series = Array.from([...new Set(values)]).sort();
    
    return series;
}

function getSeriePorAluno(alunoId) {
    const values = folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues().filter(function(row) {
        return row[indexAlunosID] == alunoId;
      }
    ).map(function(row){
      return row[indexAlunosSerie]
    });
    
    return values[0];
}

function getEscolaPorAluno(alunoId) {
    const values = folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues().filter(function(row) {
        return row[indexAlunosID] == alunoId;
      }
    ).map(function(row){
      return row[indexAlunosEscola]
    });
    
    return values[0];
}

function getTurmaPorAluno(alunoId) {
    const values = folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues().filter(function(row) {
        return row[indexAlunosID] == alunoId;
      }
    ).map(function(row){
      return row[indexAlunosTurma]
    });
    
    return values[0];
}

function getTurmas(escola, serie) {
    const values = folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues().filter(function(row) {
        return row[indexAlunosEscola] == escola && row[indexAlunosSerie].toString().includes(serie);
      }
    );
    
    var turmas = [];
    for (var i = 0; i < values.length; i++) {
      let turma = values[i][indexAlunosTurma];
      if (!turmas.includes(turma)) {
        turmas.push(turma);
      }
    }
    
    return ordenar(turmas);
}

function getAvaliacoes(pageFrom, inep) {
  
  const avaliacoes = folhaProva.getRange('A2:Z'+folhaProva.getLastRow()).getValues()
    .filter(function(e) {
      if (pageFrom == "gabarito") {
        return e[indexProvaLiberarFormulario] == 1
      } else if (pageFrom == "resultado" && inep.toLowerCase() == "semed") {
        return e[indexProvaLiberarResultadosParaSEMED] == 1
      } else if (pageFrom == "resultado") {
        return e[indexProvaLiberarResultados] == 1
      }
    }).map(function(e) {
        return {
                "id": e[indexProvaID],
                "nome": e[indexProvaNome]
              };
      }
    );

    return avaliacoes;
}

function getDisciplinas(inep=null) {
  if(
      inep==null || inep==-1 || inep=="semed"
  ) {
    return getDisciplinasTodas();
  } else {
    return getDisciplinasPorEscola(inep);
  }
}

function getDisciplinasPorEscola(inep) {
    const series = getSeriesPorEscolaINEP(inep);
    const disciplinas = folhaProvaQuestao.getRange('A1:Z'+folhaProvaQuestao.getLastRow()).getValues().filter(function(row) {
        return series.includes(row[indexFolhaProvaQuestaoSerie].toString());
      }
    ).map(function(e){
      return e[indexFolhaProvaQuestaoDisciplina];
    });

    return disciplinas.filter(onlyUnique);
;
}

function getDisciplinasPorSerie2(avaliacao, serie) {
    const values = folhaProvaQuestao.getRange(`A2:AZ${folhaProvaQuestao.getLastRow()}`)
                  .getValues().filter(function(row) {
                      return row[indexFolhaProvaQuestaoProvaRef] == avaliacao
                              && row[indexFolhaProvaQuestaoSerie].toString().includes(serie);
                    }
                  );

    var disciplinasObj = {};
    var disciplinas = [];
    for (var i = 0; i < values.length; i++) {
      let nome = values[i][indexFolhaProvaQuestaoDisciplina];
      if (!(nome in disciplinasObj)) {
        disciplinas.push(nome);
        disciplinasObj[nome] = '';
      }
    }
    
    return disciplinas;
}

function getDisciplinasTodas() {
    const values = folhaProvaQuestao.getRange('A2:Z'+folhaProvaQuestao.getLastRow()).getValues();
    
    var disciplinas = [];
    for (var i = 0; i < values.length; i++) {
      let nome = values[i][indexFolhaProvaQuestaoDisciplina];
      disciplinas.push(nome);
    }

    var unique = disciplinas.filter(onlyUnique);
    
    return unique;
}

function getSubdisciplinas2(serie, disciplina) {
     const subs = folhaProvaQuestao.getRange(`A2:AZ${folhaProvaQuestao.getLastRow()}`)
                  .getValues().filter(function(row) {
                      return row[indexFolhaProvaQuestaoSerie] == serie
                              && row[indexFolhaProvaQuestaoDisciplina] == disciplina;
                    }
                  ).map(function(e){
                    return e[indexFolhaProvaQuestaoSubDisciplina]
                  });
    
    var unique = subs.filter(onlyUnique).sort();
    
    return unique;
}

function getQuestoes(avaliacao, serie, disciplina) {
    const values = folhaProvaQuestao.getRange(`A2:AZ${folhaProvaQuestao.getLastRow()}`)
                  .getValues().filter(function(row) {
                      return row[indexFolhaProvaQuestaoProvaRef] == avaliacao
                              && row[indexFolhaProvaQuestaoSerie].toString().includes(serie)
                              && row[indexFolhaProvaQuestaoDisciplina] == disciplina;
                    }
                  );

    var questoesObj = {};
    for (var i = 0; i < values.length; i++) {
      let q = values[i][indexFolhaProvaQuestaoQuestao];
      let tipo = values[i][indexFolhaProvaQuestaoTipo];
      let enunciado = values[i][indexFolhaProvaQuestaoEnunciado];

      if (q in questoesObj) {
        
        if (!questoesObj[q]['enunciado'].includes(enunciado)) {
            questoesObj[q]['enunciado'].push(enunciado);
        }
        
        questoesObj[q]['alternativas'].push(
                                    {'alternativa': values[i][indexFolhaProvaQuestaoAlternativa],
                                      'descricao': values[i][indexFolhaProvaQuestaoDescricao],
                                      'subquestao': values[i][indexFolhaProvaQuestaoSubQuestao]
                                      } );
      } else {
        questoesObj[q] = {
          'questao': q,
          'enunciado': [enunciado],
          'tipo': tipo,
          'alternativas': [{'alternativa': values[i][indexFolhaProvaQuestaoAlternativa],
                            'descricao': values[i][indexFolhaProvaQuestaoDescricao],
                            'subquestao': values[i][indexFolhaProvaQuestaoSubQuestao]}]
        };
      }
    }
    Logger.log(questoesObj);
    
    var questoes = [];
    const keys = Object.keys(questoesObj).sort();
    for (var k = 0; k < keys.length; k++) {
      questoes.push(questoesObj[keys[k]]);
    }
    return questoes;
}

function getAlunos(avaliacao, escola, serie, turma, disciplina) {
    const values = folhaAlunos.getRange('A1:AZ'+folhaAlunos.getLastRow()).getValues().filter(function(row) {
        return row[indexAlunosProvaRef] == avaliacao
                && row[indexAlunosEscola] == escola 
                && row[indexAlunosSerie] == serie
                && row[indexAlunosTurma] == turma;
      }
    );
    
    // marcando aluno como respondeu a avaliação
    const alunosQueResponderam = folhaRespostas.getRange('A2:AZ'+folhaRespostas.getLastRow()).getValues().filter(function(row) {
          return row[indexRespostasProvaRef] == avaliacao
              && row[indexRespostasEscola] == escola
              && row[indexRespostasDisciplina] == disciplina
              && row[indexRespostasSerie] == serie
              && row[indexRespostasTurma] == turma;
      }).map(function(e) {
        return e[indexRespostasIDAluno]
      });   
    
    var alunos = [];
    for (var i = 0; i < values.length; i++) {
      let nome = values[i][indexAlunosNome];
      let id = values[i][indexAlunosID];
      let respondeu = alunosQueResponderam.includes(id) ? 1 : 0;

      alunos.push(nome + "|" + id + "|" + respondeu);
    }

    return alunos;
}

function getRespostaAluno(avaliacao, disciplina, idAluno) {
    const values = folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow()).getValues().filter(function(row) {
        return row[indexRespostasProvaRef] == avaliacao
                && row[indexRespostasDisciplina] == disciplina 
                && row[indexRespostasIDAluno] == idAluno;
      }
    ).map(function(e) {
          let resposta = {'escreveonome': e[indexRespostasEscreveONome],
                          'respostas': []};
          for (var i = indexRespostasEscreveONome+1; i < e.length; i++) {
            resposta['respostas'].push(e[i]);
          }
          return resposta;
        });

    
    return (values[0] == null) ? [] : values[0];
}

function getAlunosCorrecao(avaliacao, escola, serie, turma, disciplina) {
    const values = folhaAlunos.getRange('A1:AZ'+folhaAlunos.getLastRow()).getValues().filter(function(row) {
        return row[indexAlunosProvaRef] == avaliacao
                && row[indexAlunosEscola] == escola 
                && row[indexAlunosSerie].toString().includes(serie)
                && row[indexAlunosTurma].toString().includes(turma);
      }
    );

    const alunosID = values.map(function(e){
          return e[indexAlunosID]
        });
   
      // marcando aluno como respondeu a avaliação
      const alunosQueResponderam = folhaCorrecao.getRange('A2:AZ'+folhaCorrecao.getLastRow()).getValues().filter(function(row) {
          return row[indexCorrecaoProvaRef] == avaliacao
              && row[indexCorrecaoDisciplina] == disciplina
              && alunosID.includes(row[indexCorrecaoIDAluno]);
      });
      
      let alunosQueResponderamObj = {};
      alunosQueResponderam.forEach((element, index) => {
        alunosQueResponderamObj[element[indexCorrecaoIDAluno]] = element;
      });
      
    var alunos = [];
    for (var i = 0; i < values.length; i++) {
      let nome = values[i][indexAlunosNome];
      let id = values[i][indexAlunosID];
      let respondeu = 0;
      let escrevenome = "-";
      let acertos = "-";
      let erros = "-";
      let nivel = "-";
      if (id in alunosQueResponderamObj) {
        const obj = alunosQueResponderamObj[id];
        
        respondeu = 1;
        escrevenome = obj[indexCorrecaoEscreveONome]
        acertos = obj[indexCorrecaoAcertos];
        erros = obj[indexCorrecaoErros];
        nivel = obj[indexCorrecaoCategoria];
      }
      
      alunos.push(nome + "|" + respondeu + "|" + escrevenome + "|" + acertos + "|" + erros + "|" + nivel);
    }

    return alunos;
}

function getResultadoSabeEscreverONome(avaliacao, escola, serie, disciplina, turma=-1) {
    
      const alunosQueResponderam = folhaRespostas.getRange('A2:AZ'+folhaRespostas.getLastRow()).getValues().filter(function(row) {
          return row[indexRespostasProvaRef] == avaliacao
              && (escola == -1 || escola.includes('--') || row[indexRespostasEscola] == escola)
              && row[indexRespostasDisciplina] == disciplina
              && row[indexRespostasSerie] == serie
              && (turma == -1 || turma == "-1" || row[indexRespostasTurma] == turma);
      });
      
      let qtdSim = 0;
      let qtdNao = 0;

      let alunosContabilizados = [];

      alunosQueResponderam.forEach((element, index) => {
        if (!alunosContabilizados.includes(element[indexRespostasIDAluno])){
          if (element[indexRespostasEscreveONome] == "SIM") {
            qtdSim += 1;
          } else {
            qtdNao += 1;
          }
          alunosContabilizados.push(element[indexRespostasIDAluno]);
        }
      });
      
    return [qtdSim, qtdNao];
}

function getAlunosCorrecaoPorHabilidade(avaliacao, escola, serie, turma, disciplina) {
    const values = folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues().filter(function(row) {
        return row[indexAlunosProvaRef] == avaliacao
                && row[indexAlunosEscola] == escola 
                && row[indexAlunosSerie].toString().includes(serie)
                && row[indexAlunosTurma].toString().includes(turma);
      }
    );

    const alunosID = values.map(function(e){
          return e[indexAlunosID]
        });
   
      // marcando aluno como respondeu a avaliação
      const alunosQueResponderam = folhaCorrecaoPorHabilidade.getRange('A2:Z'+folhaCorrecaoPorHabilidade.getLastRow()).getValues().filter(function(row) {
          return row[indexCorrecaoPorHabilidadeProvaRef] == avaliacao
              && row[indexCorrecaoPorHabilidadeDisciplina] == disciplina
              && alunosID.includes(row[indexCorrecaoPorHabilidadeIDAluno]);
      });
      
      let alunosQueResponderamObj = {};
      alunosQueResponderam.forEach((element, index) => {
        let idAluno = element[indexCorrecaoPorHabilidadeIDAluno];
        if (!(idAluno in alunosQueResponderamObj)){
          alunosQueResponderamObj[element[indexCorrecaoPorHabilidadeIDAluno]] = [];  
        }
        alunosQueResponderamObj[element[indexCorrecaoPorHabilidadeIDAluno]].push(element);
      });

    var habilidades = [];
    
    var alunos = [];
    for (var i = 0; i < values.length; i++) {
      let nome = values[i][indexAlunosNome];
      let id = values[i][indexAlunosID];
      let desempenho = [];
      
      if (id in alunosQueResponderamObj) {
        const array = alunosQueResponderamObj[id];
        
        for (var a=0; a < array.length; a++) {
          let aux = array[a];

          desempenho.push(`${aux[indexCorrecaoPorHabilidadeAcertos]} / ${(aux[indexCorrecaoPorHabilidadeAcertos] + aux[indexCorrecaoPorHabilidadeErros])}`);

          const h = aux[indexCorrecaoPorHabilidadeHabilidade];
          if (!(habilidades.includes(h))) {
              habilidades.push(h);
          }
        }        
      }
      
      alunos.push({'nome':nome, 'desempenho':desempenho});
    }

    return [habilidades, alunos];
}

function getQtdAlunos(avaliacao, escola, serie, turma=-1) {
  if (escola == null || escola.length == 0) {
    return folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues().filter(function(row) {          
          return row[indexAlunosProvaRef] == avaliacao && row[indexAlunosSerie].toString() == serie;          
        }
      ).length;

  } else {

    return folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues().filter(function(row) {
            let test = row[indexAlunosProvaRef] == avaliacao
                    && row[indexAlunosEscola] == escola 
                    && row[indexAlunosSerie].toString() == serie;

            if (turma == -1 || turma == "-1") {
              return test;
            } else {
              return test && row[indexAlunosTurma] == turma;
            }
          }
        ).length;  
  }
}

function getEscola(inep) {
  const escolas = folhaConfiguracao.getRange('A1:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row){
        return row[indexConfigAno] == anoPreMatricula
                && row[indexConfigINEP]== inep;
      }
    ).map(function (e) {
      return e[indexConfigEscola]
    });;
  
  return escolas;

}

function getEscolas(serie) {
  const escolas = folhaConfiguracao.getRange('A1:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row){
        return row[indexConfigAno] == anoPreMatricula && row[indexConfigSeries].toString().includes(serie);
      }
    ).map(function (e) {
      return e[indexConfigEscola]
    });;
  
  return {'status': true, 'message': escolas};
}

function getEscolasTodas() {
  const escolas = folhaConfiguracao.getRange('A1:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row){
        return row[indexConfigAno] == anoPreMatricula && row[indexConfigEscola].toUpperCase() != 'SEMED';
      }
    ).map(function (e) {
      return {'nome':e[indexConfigEscola], 'inep': e[indexConfigINEP]}
    });;
  
  return {'status': true, 'message': escolas};
}

function getParticipacao(avaliacao, inep_escola, serie, disciplina, turma) {
  if (inep_escola == null || inep_escola == -1 || inep_escola.toUpperCase() == "SEMED") {
      Logger.log('condicao 1');
    return getParticipacao2(avaliacao, serie, disciplina, turma);
  } else {
    Logger.log('condicao 2');
    return getParticipacao1(avaliacao, inep_escola, serie, disciplina, turma);
  }
}

function getParticipacao1(avaliacao, inep_escola, serie, disciplina, turma=-1) {
    const escolas = folhaConfiguracao.getRange('A2:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row) {
        return row[indexConfigINEP].toString() == inep_escola;
      }
    ).map(function (e) {
      return e[indexConfigEscola]
    });

    var totalPresenca = 0;
    var totalAusencia = 0;

    Logger.log('inep_escola: ' + inep_escola);
    Logger.log('escolas: ' + escolas);

    for (var i=0; i < escolas.length; i++) {
        let escola = escolas[i];
              
        const qtdAlunos = getQtdAlunos(avaliacao, escola, serie, turma);
        Logger.log('qtdAlunos1: ' + qtdAlunos);
            
        const respostasIDAlunos = folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow()).getValues().filter(function(row) {
            let test = row[indexRespostasProvaRef] == avaliacao
                    && row[indexRespostasDisciplina] == disciplina 
                    && row[indexRespostasEscola] == escola
                    && row[indexRespostasSerie] == serie;
              if (turma == -1 || turma == "-1") {
                    return test;
              } else {
                return test && row[indexRespostasTurma] == turma;
              }
          }
        ).map(function(e) {
          return e[indexRespostasIDAluno]
        });
        Logger.log('alunos que responderam por série: ' + respostasIDAlunos.length);

        var respostasUnicas = respostasIDAlunos.filter(onlyUnique);
        totalPresenca += respostasUnicas.length;

        totalAusencia += qtdAlunos - respostasUnicas.length;        
    }

  return [totalPresenca, totalAusencia];
}

function getParticipacao2(avaliacao, serie, disciplina, turma=-1) {
    var totalPresenca = 0;
    var totalAusencia = 0;
    
        const qtdAlunos = getQtdAlunos(avaliacao, null, serie, turma);
        Logger.log('qtdAlunos2: ' + qtdAlunos);

        const respostasIDAlunos = folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow()).getValues().filter(function(row) {
            let test = row[indexRespostasProvaRef] == avaliacao
                    && row[indexRespostasDisciplina] == disciplina 
                    && row[indexRespostasSerie] == serie;

              if (turma == -1 || turma == "-1") {
                    return test;
              } else {
                return test && row[indexRespostasTurma] == turma;
              }
          }
        ).map(function(e){
          return e[indexRespostasIDAluno]
        });

        var respostasUnicas = respostasIDAlunos.filter(onlyUnique);
    
        totalPresenca += respostasUnicas.length;

        totalAusencia += qtdAlunos - respostasUnicas.length;
       

    return [totalPresenca, totalAusencia];
}

function getDesempenho(avaliacao, inep_escola, serie, disciplina, turma, subdisciplina) {
   if (inep_escola == null || inep_escola == -1 || inep_escola.toUpperCase() == "SEMED" ) {
    return getDesempenho2(avaliacao, serie, disciplina, subdisciplina);
  } else {
    return getDesempenho1(avaliacao, inep_escola, serie, disciplina, turma, subdisciplina);
  }
}

function getDesempenho1(avaliacao, inep_escola, serie, disciplina, turma=-1, subdisciplina) {
    const escolas = folhaConfiguracao.getRange('A2:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row){
        return row[indexConfigINEP].toString() == inep_escola;
      }
    ).map(function (e) {
      return e[indexConfigEscola]
    });;

    var totalAcertos = 0;
    var totalErros = 0;
    
    for (var i=0; i < escolas.length; i++) {
      let escola = escolas[i];
            
      const desempenho = folhaCorrecao.getRange('A1:Z'+folhaCorrecao.getLastRow()).getValues().filter(function(row) {
          let test = row[indexCorrecaoProvaRef] == avaliacao
                  && row[indexCorrecaoDisciplina] == disciplina 
                  && row[indexCorrecaoEscola] == escola
                  && row[indexCorrecaoSerie] == serie
                  && row[indexCorrecaoSubDisciplina] == subdisciplina;

          if (turma == -1 || turma == "-1") {
            return test;
          } else {
            return test && row[indexCorrecaoTurma] == turma;
          }
        }
      ).map(function(e){
        return [e[indexCorrecaoAcertos], e[indexCorrecaoErros]]
      });

      for (var i=0; i < desempenho.length; i++) {
          totalAcertos += desempenho[i][0];
          totalErros += desempenho[i][1];
      }      
  }

  return [totalAcertos, totalErros];
}

function getDesempenho2(avaliacao, serie, disciplina, subdisciplina) {
    var totalAcertos = 0;
    var totalErros = 0;
                    
        const desempenho = folhaCorrecao.getRange('A1:Z'+folhaCorrecao.getLastRow()).getValues().filter(function(row) {
            return row[indexCorrecaoProvaRef] == avaliacao
                    && row[indexCorrecaoDisciplina] == disciplina 
                    && row[indexCorrecaoSerie] == serie
                    && row[indexCorrecaoSubDisciplina] == subdisciplina;
          }
        ).map(function(e){
          return [e[indexCorrecaoAcertos], e[indexCorrecaoErros]]
        });

        for (var i=0; i < desempenho.length; i++) {
            totalAcertos += desempenho[i][0];
            totalErros += desempenho[i][1];
        }        

  return [totalAcertos, totalErros];
}

function getCategorias(avaliacao, inep_escola, serie, disciplina, turma, subdisciplina){
  if (inep_escola == null || inep_escola == -1 || inep_escola.toUpperCase() == "SEMED" ) {
    return getCategorias2(avaliacao, serie, disciplina, subdisciplina);
  } else {
    return getCategorias1(avaliacao, inep_escola, serie, disciplina, turma, subdisciplina);
  }
}

function getCategorias1(avaliacao, inep_escola, serie, disciplina, turma= -1, subdisciplina) {
    const escolas = folhaConfiguracao.getRange('A2:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row){
        return row[indexConfigINEP].toString() == inep_escola;
      }
    ).map(function (e) {
      return e[indexConfigEscola]
    });;

    let categoriaMuitoBaixo= 0;
    let categoriaBaixo= 0;
    let categoriaMedio= 0;
    let categoriaAlto= 0;
    

    for (var i=0; i< escolas.length; i++){
      let escola = escolas[i];
                   
        const resultCategorias = folhaCorrecao.getRange('A1:Z'+folhaCorrecao.getLastRow()).getValues().filter(function(row) {
              let test = row[indexCorrecaoProvaRef] == avaliacao
                        && row[indexCorrecaoEscola] == escola
                        && row[indexCorrecaoDisciplina] == disciplina 
                        && row[indexCorrecaoSerie] == serie
                        && row[indexCorrecaoSubDisciplina] == subdisciplina ;
              if (turma == -1 || turma == "-1"){
                return test;
              } else {
                return test && row[indexCorrecaoTurma] == turma;
              }
          }
        );
        const categorias = distinctRows(resultCategorias).map(function(e){
          return e[indexCorrecaoCategoria]
        });

        for (var j=0; j < categorias.length; j++) {
            if (categorias[j] == "MUITO BAIXO"){
              categoriaMuitoBaixo += 1;
            } else if (categorias[j] == "BAIXO"){
              categoriaBaixo += 1;
            } else if (categorias[j] == "MÉDIO"){
              categoriaMedio += 1;
            }else if (categorias[j] == "ALTO"){
              categoriaAlto += 1;
            }
        }        
          
  }
  
  return [categoriaMuitoBaixo, categoriaBaixo, categoriaMedio, categoriaAlto];
}

function getCategorias2(avaliacao, serie, disciplina, subdisciplina) {
    let categoriaMuitoBaixo= 0;
    let categoriaBaixo= 0;
    let categoriaMedio= 0;
    let categoriaAlto= 0;
        
    const resultCategorias = folhaCorrecao.getRange('A1:Z'+folhaCorrecao.getLastRow()).getValues().filter(function(row) {
        return row[indexCorrecaoProvaRef] == avaliacao
                && row[indexCorrecaoDisciplina] == disciplina 
                && row[indexCorrecaoSerie] == serie
                && row[indexCorrecaoSubDisciplina] == subdisciplina ;
      }
    );
    const categorias = distinctRows(resultCategorias).map(function(e){
      return e[indexCorrecaoCategoria]
    });
    
    for (var i=0; i < categorias.length; i++) {
        if (categorias[i] == "MUITO BAIXO"){
          categoriaMuitoBaixo += 1;
        } else if (categorias[i] == "BAIXO"){
          categoriaBaixo += 1;
        } else if (categorias[i] == "MÉDIO"){
          categoriaMedio += 1;
        }else if (categorias[i] == "ALTO"){
          categoriaAlto += 1;
        }
    }        
  return [categoriaMuitoBaixo, categoriaBaixo, categoriaMedio, categoriaAlto];
}

function getCategoriasConceituais(avaliacao, inep_escola, serie, disciplina, indexQuestao) {
    let escola = null;
    if (inep_escola != null && inep_escola != 'semed' && inep_escola != -1) {
      const escolas = folhaConfiguracao.getRange('A2:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row){
          return row[indexConfigINEP].toString() == inep_escola;
        }
      ).map(function (e) {
        return e[indexConfigEscola]
      });

      
      if (escolas.length == 1) {
        escola = escolas[0];
      }    
    }

    let questaoEnunciado = null;
    let descricao = [];
    let alternativas = [];
    let qtdRespostas = [];

    indexQuestao = parseInt(indexQuestao);

    let questoesRow = folhaProvaQuestao.getRange('A1:Z' + folhaProvaQuestao.getLastRow()).getValues().filter(function(row) {
        return row[indexFolhaProvaQuestaoProvaRef] == avaliacao 
                && row[indexFolhaProvaQuestaoSerie] == serie 
                && row[indexFolhaProvaQuestaoDisciplina] == disciplina;
    }).map(function(row){
      return row[indexFolhaProvaQuestaoQuestao]
    });
    questoesRow = questoesRow.filter(onlyUnique);
    let questaoID = questoesRow[indexQuestao];
    
    folhaProvaQuestao.getRange('A1:Z' + folhaProvaQuestao.getLastRow()).getValues().filter(function(row) {
        return row[indexFolhaProvaQuestaoProvaRef] == avaliacao
                && row[indexFolhaProvaQuestaoSerie] == serie 
                && row[indexFolhaProvaQuestaoDisciplina] == disciplina 
                && row[indexFolhaProvaQuestaoQuestao] == questaoID;
    }).map(function(row){
        if (questaoEnunciado == null) {
          questaoEnunciado = row[indexFolhaProvaQuestaoEnunciado];
        }
        alternativas.push(row[indexFolhaProvaQuestaoAlternativa]);
        descricao.push(row[indexFolhaProvaQuestaoDescricao]);
        qtdRespostas.push(0);
        
        return true;
    });

    const alunosIDPorSerie = folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues().filter(function(row) {
        return row[indexAlunosProvaRef] == avaliacao
                 && ((escola == null) ? true : row[indexAlunosEscola] == escola)
                 && row[indexAlunosSerie].toString() == serie;
      }
    ).map(function(e) {
      return e[indexAlunosID]
    });
    
    folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow()).getValues().filter(function(row) {
        return row[indexRespostasProvaRef] == avaliacao
                && row[indexRespostasDisciplina] == disciplina 
                && alunosIDPorSerie.includes(row[indexRespostasIDAluno]);
      }
    ).map(function(e) {
      let r = e[indexRespostasEscreveONome + 1 + indexQuestao];
      for (var i=0; i<alternativas.length;i++) {
        if (alternativas[i] == r){
          qtdRespostas[i] = qtdRespostas[i] + 1;
        }
      }
      
      return true;
    });

  return {
    'descricao': descricao,
    'alternativas': alternativas,
    'qtd': qtdRespostas
  };
}

function getCategoriasConceituaisNiveis(avaliacao, inep_escola, serie, disciplina, indexQuestao) {
    let escola = null;
    if (inep_escola != null && inep_escola != 'semed' && inep_escola != -1) {
      const escolas = folhaConfiguracao.getRange('A2:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row){
          return row[indexConfigINEP].toString() == inep_escola;
        }
      ).map(function (e) {
        return e[indexConfigEscola]
      });

      
      if (escolas.length == 1) {
        escola = escolas[0];
      }    
    }

    let mapObj = {
      "MUITO BAIXO" : 0, 
      "BAIXO" : 0,
      "INTERMEDIÁRIO" : 0,      
      "ADEQUADO" : 0
    };

    indexQuestao = parseInt(indexQuestao);

    let questoesRow = folhaProvaQuestao.getRange('A1:Z' + folhaProvaQuestao.getLastRow()).getValues().filter(function(row) {
        return row[indexFolhaProvaQuestaoProvaRef] == avaliacao 
                && row[indexFolhaProvaQuestaoSerie] == serie 
                && row[indexFolhaProvaQuestaoDisciplina] == disciplina;
    }).map(function(row){
      return row[indexFolhaProvaQuestaoQuestao]
    });
    questoesRow = questoesRow.filter(onlyUnique);
    let questaoID = questoesRow[indexQuestao];
    
    // folhaProvaQuestao.getRange('A1:Z' + folhaProvaQuestao.getLastRow()).getValues().filter(function(row) {
    //     return row[indexFolhaProvaQuestaoProvaRef] == avaliacao
    //             && row[indexFolhaProvaQuestaoSerie] == serie 
    //             && row[indexFolhaProvaQuestaoDisciplina] == disciplina 
    //             && row[indexFolhaProvaQuestaoQuestao] == questaoID;
    // }).map(function(row){
    //     alternativas.push(row[indexFolhaProvaQuestaoAlternativa]);
    //     qtdRespostas.push(0);
        
    //     return true;
    // });

    const alunosIDPorSerie = folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues().filter(function(row) {
        return row[indexAlunosProvaRef] == avaliacao
                 && ((escola == null) ? true : row[indexAlunosEscola] == escola)
                 && row[indexAlunosSerie].toString() == serie;
      }
    ).map(function(e) {
      return e[indexAlunosID]
    });
    
    folhaCorrecaoConceitualNivel.getRange('A1:AZ'+folhaCorrecaoConceitualNivel.getLastRow()).getValues().filter(function(row) {
        return row[indexCorrecaoConceitualNivelProvaRef] == avaliacao
                && row[indexCorrecaoConceitualNivelDisciplina] == disciplina 
                && alunosIDPorSerie.includes(row[indexCorrecaoConceitualNivelIDAluno]);
      }
    ).map(function(e) {
      let nivel = e[indexCorrecaoConceitualNivelCategoria];
      if (nivel in mapObj) {
        mapObj[nivel] += 1;
      } else {
        mapObj[nivel] = 0;
      }
      
      return true;
    });

  const chaves = Object.keys(mapObj);
  const valores = Object.values(mapObj);
  
  Logger.log({
    'alternativas': chaves,
    'qtd': valores
  });

  return {
    'alternativas': chaves,
    'qtd': valores
  };
}


function getQuestoesConceituais(avaliacao, serie, disciplina) {
    let questaoLida = [];
    let indexQuestao = 0;
    let indexQuestaoAux = 0;
    let questoes = [];

    folhaProvaQuestao.getRange('A1:Z' + folhaProvaQuestao.getLastRow()).getValues().filter(function(row) {
        return row[indexFolhaProvaQuestaoProvaRef] == avaliacao 
                && row[indexFolhaProvaQuestaoSerie] == serie 
                && row[indexFolhaProvaQuestaoDisciplina] == disciplina;
    }).map(function(row) {        
        let q = row[indexFolhaProvaQuestaoQuestao];

        if (row[indexFolhaProvaQuestaoTipo] == "objetiva") {
          
          if (!questaoLida.includes(q)) {
            questaoLida.push(q);
            indexQuestao += 1;
          }

          return;
        }
        
        let tipo = row[indexFolhaProvaQuestaoTipo];

        if (!questaoLida.includes(q)) {
          questoes.push({
            'index': indexQuestao,
            'questao': q,
            'enunciado': row[indexFolhaProvaQuestaoEnunciado],
            'tipo': tipo,
            'subquestao' : []
          });          
          questaoLida.push(q);
          indexQuestao += 1;
          indexQuestaoAux += 1;
        } else if (tipo == 'conceitual-nivel') {
          let lastIndexQuestaoAux = indexQuestaoAux - 1;
          questoes[lastIndexQuestaoAux]['subquestao'].push(row[indexFolhaProvaQuestaoSubQuestao]);
        }
        
    });

    // Remover duplicatas em subquestao
    questoes.forEach(obj => {
      obj.subquestao = Array.from(new Set(obj.subquestao)).sort((a, b) => a - b);
    });

  return questoes.filter(onlyUnique);
}

function getHabilidadesDescricao(avaliacao, serie, disciplina) {
    
    let habilidades = folhaHabilidades.getRange('A1:Z'+folhaHabilidades.getLastRow()).getValues()
      .filter(function(row){
        return row[indexHabilidadesProvaRef] == avaliacao
                && row[indexHabilidadesSerie] == serie
                && row[indexHabilidadesDisciplina] == disciplina
      }).map(function(row){
        return row[indexHabilidadesCode] + " - " + row[indexHabilidadesDescricao];
      });

    return habilidades.filter(onlyUnique).sort();
}

function getHabilidadesPorProva(avaliacao, serie, disciplina){
      let habilidades = folhaProvaQuestao.getRange('A2:AZ'+folhaProvaQuestao.getLastRow())
                              .getValues().filter(function(row){

                                  return row[indexFolhaProvaQuestaoProvaRef] == avaliacao
                                          && row[indexFolhaProvaQuestaoSerie] == serie
                                          && row[indexFolhaProvaQuestaoDisciplina] == disciplina
                                          && row[indexFolhaProvaQuestaoTipo] == "objetiva"
                                          && row[indexFolhaProvaQuestaoCorreta] == 1
                              }).map(function(row){
                                  return row[indexFolhaProvaQuestaoHabilidade];
                              });
      
      return habilidades.filter(onlyUnique).sort();
}

function getHabilidadesPorProvaSubDisciplina(avaliacao, serie, disciplina, subDisciplina){
      let habilidades = folhaProvaQuestao.getRange('A2:AZ'+folhaProvaQuestao.getLastRow())
                              .getValues().filter(function(row){

                                  return row[indexFolhaProvaQuestaoProvaRef] == avaliacao
                                          && row[indexFolhaProvaQuestaoSerie] == serie
                                          && row[indexFolhaProvaQuestaoDisciplina] == disciplina
                                          && row[indexFolhaProvaQuestaoSubDisciplina] == subDisciplina
                                          && row[indexFolhaProvaQuestaoTipo] == "objetiva"
                                          && row[indexFolhaProvaQuestaoCorreta] == 1
                              }).map(function(row){
                                  return row[indexFolhaProvaQuestaoHabilidade];
                              });
      
      return habilidades.filter(onlyUnique).sort();
}

function getDesempenhoPorHabilidade(avaliacao, escola, serie, disciplina, turma=-1, subdisciplina) {
    let alunosID = [];

    if (escola == null || escola == -1 || escola.includes('--')) {
      alunosID = folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues()
        .filter(function(row) {
            return row[indexAlunosProvaRef] == avaliacao && row[indexAlunosSerie].toString() == serie;
          }
        ).map(function(e){
          return e[indexAlunosID]
        });
    } else {
      alunosID = folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues()
        .filter(function(row) {
            let test = row[indexAlunosProvaRef] == avaliacao
                    && row[indexAlunosSerie].toString() == serie
                    && row[indexAlunosEscola].toString() == escola;
            
            if (turma == -1 || turma == "-1") {
              return test;
            } else {
              return test && row[indexAlunosTurma] == turma;
            }
          }
        ).map(function(e){
          return e[indexAlunosID]
        });
    }

    return getDesempenhoDosAlunosPorHabilidade(avaliacao, serie, alunosID, disciplina, subdisciplina);
}

function getDesempenhoDosAlunosPorHabilidade(avaliacao, serie, alunos, disciplina, subdisciplina) {
    let countObj = {};

    let habilidadesDaProva = getHabilidadesPorProvaSubDisciplina(avaliacao, serie, disciplina, subdisciplina);
    
    const map = folhaCorrecaoPorHabilidade.getRange('A1:Z'+folhaCorrecaoPorHabilidade.getLastRow())
                        .getValues().filter(function(row) {
                            return row[indexCorrecaoPorHabilidadeProvaRef] == avaliacao 
                                    && row[indexCorrecaoPorHabilidadeDisciplina] == disciplina
                                    && row[indexCorrecaoPorHabilidadeSubDisciplina] == subdisciplina
                                    && alunos.includes(row[indexCorrecaoPorHabilidadeIDAluno]);
                          }
                        ).map(function(e){
                          let hab = e[indexCorrecaoPorHabilidadeHabilidade];
                          if (!habilidadesDaProva.includes(hab)) {
                            return null;                                                            
                          }

                          return {
                                  'habilidade': hab,
                                  'categoria': e[indexCorrecaoPorHabilidadeCategoria]
                          }
                        });

    for (var i=0; i < map.length; i++) {
        if (map[i] == null) {
          continue;
        }

        let habilidade = map[i]['habilidade'];
        let categoria = map[i]['categoria'];

        if (!(habilidade in countObj)) {
          countObj[habilidade] = {
            "MUITO BAIXO": 0,
            "BAIXO": 0,
            "MÉDIO": 0,
            "ALTO": 0
          };
        }
        countObj[habilidade][categoria] += 1;
    }

    let habilidades = Object.keys(countObj);
    
    let arrayMuitoBaixo = [];
    let arrayBaixo = [];
    let arrayMedio = [];
    let arrayAlto = [];

    let finalHabilidades = [];
    for (var index in habilidades) {
        let key = habilidades[index];

        const qtdMuitoBaixo = countObj[key]['MUITO BAIXO'];
        const qtdBaixo = countObj[key]['BAIXO'];
        const qtdMedio = countObj[key]['MÉDIO'];
        const qtdAlto = countObj[key]['ALTO'];

        if ((qtdMuitoBaixo + qtdBaixo + qtdMedio + qtdAlto) == 0) {
          continue;
        }

        finalHabilidades.push(key);

        arrayMuitoBaixo.push(qtdMuitoBaixo);
        arrayBaixo.push(qtdBaixo);
        arrayMedio.push(qtdMedio);
        arrayAlto.push(qtdAlto);
    }         

    let result = {
      'labels': finalHabilidades,
      'datasets': [
        {
            label: "MUITO BAIXO",
            backgroundColor: '#fb0505',
            data: arrayMuitoBaixo
        },
        {
            label: "BAIXO",
            backgroundColor: 'orange',
            data: arrayBaixo
        },
        {
            label: "MÉDIO",
            backgroundColor: '#79dd75',
            data: arrayMedio
        },
        {
            label: "ALTO",
            backgroundColor: '#1388ea',
            data: arrayAlto
        }
      ]
    };
    
    return result;
}

function getGabarito(avaliacao, disciplina, serie) {
       let gabarito = folhaProvaQuestao.getRange('A1:AZ'+folhaProvaQuestao.getLastRow()).getValues().filter(function(row){
              return row[indexFolhaProvaQuestaoProvaRef] == avaliacao
                      && row[indexFolhaProvaQuestaoDisciplina] == disciplina 
                      && row[indexFolhaProvaQuestaoSerie] == serie
                      && row[indexFolhaProvaQuestaoTipo] == "objetiva"
                      && row[indexFolhaProvaQuestaoCorreta] == 1
          }).map(function(x){
            return x[indexFolhaProvaQuestaoAlternativa];
          });

          return gabarito;
}

function getGabaritoPorSubdisciplina(avaliacao, disciplina, serie, subDisciplina) {
       let gabarito = folhaProvaQuestao.getRange('A1:AZ'+folhaProvaQuestao.getLastRow()).getValues().filter(function(row){
              return row[indexFolhaProvaQuestaoProvaRef] == avaliacao
                      && row[indexFolhaProvaQuestaoDisciplina] == disciplina
                      && row[indexFolhaProvaQuestaoSubDisciplina] == subDisciplina 
                      && row[indexFolhaProvaQuestaoSerie] == serie
                      && row[indexFolhaProvaQuestaoTipo] == "objetiva"
                      && row[indexFolhaProvaQuestaoCorreta] == 1
          }).map(function(x){
            return x[indexFolhaProvaQuestaoAlternativa];
          });

          return gabarito;
}

function getNumeroPrimeiraQuestaoSubDisciplina(avaliacao, disciplina, serie, subDisciplina) {
  let values = folhaProvaQuestao
    .getRange('A1:AZ' + folhaProvaQuestao.getLastRow())
    .getValues();

  for (let i = 0; i < values.length; i++) {
    let row = values[i];

    if (row[indexFolhaProvaQuestaoProvaRef] == avaliacao
      && row[indexFolhaProvaQuestaoDisciplina] == disciplina
      && row[indexFolhaProvaQuestaoSubDisciplina] == subDisciplina 
      && row[indexFolhaProvaQuestaoSerie] == serie
      && row[indexFolhaProvaQuestaoTipo] == "objetiva"
      && row[indexFolhaProvaQuestaoCorreta] == 1) {

      return parseInt(row[indexFolhaProvaQuestaoQuestao]); // sai imediatamente
    }
  }

  return null; // caso não encontre
}

function getSubdisciplinas(avaliacao, disciplina, serie) {
       let subdisciplinas = folhaProvaQuestao.getRange('A1:AZ'+folhaProvaQuestao.getLastRow()).getValues().filter(function(row){
              return row[indexFolhaProvaQuestaoProvaRef] == avaliacao
                      && row[indexFolhaProvaQuestaoDisciplina] == disciplina
                      && row[indexFolhaProvaQuestaoSerie] == serie
                      && row[indexFolhaProvaQuestaoTipo] == "objetiva"
                      && row[indexFolhaProvaQuestaoCorreta] == 1
          }).map(function(x){
            return x[indexFolhaProvaQuestaoSubDisciplina];
          });

          return subdisciplinas.filter(onlyUnique);
}

/**
 * Remove linhas duplicadas de um array 2D (baseado em todas as colunas).
 *
 * @param {Array[]} data - Array 2D (ex: resultado de getValues()).
 * @return {Array[]} - Array 2D só com linhas únicas.
 */
function distinctRows(data) {
  const vistos = new Set();
  return data.filter(row => {
    const chave = JSON.stringify(row);
    if (vistos.has(chave)) {
      return false;
    }
    vistos.add(chave);
    return true;
  });
}



