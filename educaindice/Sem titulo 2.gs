function preencherQuantitativoDigitalizado() {
   let avaliacao = 1;

    let escolas = folhaConfiguracao.getRange('A2:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row){
        return row[indexConfigINEP].toString().length > 0;
      }
    ).map(function (e) {
      return e[indexConfigEscola]
    });;

    escolas = escolas.reverse();

    let linha = 2;

    for (var e=0; e<escolas.length; e++){
      let escola = escolas[e];

      let series = getSeriesPorEscola(escola);
      
      for (var s=0; s < series.length; s++){
        let serie = series[s];

        let turmas = getTurmas(escola, serie);
        for (var t=0; t< turmas.length; t++){
          let turma = turmas[t];

        const alunosID = folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues().filter(function(row) {
            return row[indexAlunosProvaRef] == avaliacao
                    && row[indexAlunosEscola] == escola 
                    && row[indexAlunosSerie].toString() == serie
                    && row[indexAlunosTurma].toString() == turma;
          }
        ).map(function(e){
          return e[indexAlunosID]
        });
        
        let disciplinas = getDisciplinasPorSerie2(avaliacao, serie);
        for (var d = 0; d < disciplinas.length; d++) {

          // let disciplina = disciplinas[d]['nome'];
          let disciplina = disciplinas[d];
            
            const respostasIDAlunos = folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow()).getValues().filter(function(row) {
                return row[indexRespostasProvaRef] == avaliacao
                        && row[indexRespostasDisciplina] == disciplina 
                        && alunosID.includes(row[indexRespostasIDAluno]);
              }
            ).map(function(e){
              return e[indexRespostasIDAluno]
            });

            var respostas = respostasIDAlunos.filter(onlyUnique);

            const correcoesIDAlunos = folhaCorrecao.getRange('A1:AZ'+folhaCorrecao.getLastRow()).getValues().filter(function(row) {
                return row[indexCorrecaoProvaRef] == avaliacao
                        && row[indexCorrecaoDisciplina] == disciplina 
                        && alunosID.includes(row[indexCorrecaoIDAluno]);
              }
            ).map(function(e){
              return e[indexCorrecaoIDAluno]
            });

            var correcoes = correcoesIDAlunos.filter(onlyUnique);
            
            Logger.log(escola+ " "+ serie+ " "+ disciplina+ " "+ alunosID.length+ " "+ respostas.length);
            folhaQuantitativo.getRange(`A${linha}`).setValue(escola);
            folhaQuantitativo.getRange(`B${linha}`).setValue(serie);
            folhaQuantitativo.getRange(`C${linha}`).setValue(turma);
            folhaQuantitativo.getRange(`D${linha}`).setValue(disciplina);
            folhaQuantitativo.getRange(`E${linha}`).setValue(alunosID.length);
            folhaQuantitativo.getRange(`F${linha}`).setValue(respostas.length);
            folhaQuantitativo.getRange(`G${linha}`).setValue(correcoes.length);

            if (respostas.length > correcoes.length) {
              let respostaSemCorrecao = respostas.filter(n => !correcoes.includes(n));
              respostaSemCorrecao = [...new Set(respostaSemCorrecao)];
              for(var a =0; a < respostaSemCorrecao.length; a++){
                let aluno = respostaSemCorrecao[a];
                syncResultsParaUmAluno(avaliacao, serie, disciplina, aluno);
              }
            }

            linha++;
           }
        }
      }
    }
}

function preencherFolhaCorrecaoParaUmAluno(avaliacao, serie, disciplina, idAluno, isUpdate) {
    let escola = getEscolaPorAluno(idAluno);
    let turma = getTurmaPorAluno(idAluno);
    
    let subdisciplinas = getSubdisciplinas(avaliacao, disciplina, serie);
    Logger.log(subdisciplinas);
    for (var i=0; i<subdisciplinas.length; i++){
      let subdisciplina = subdisciplinas[i];
      Logger.log("\n\n"+subdisciplina);
      let gabarito = getGabaritoPorSubdisciplina(avaliacao, disciplina, serie, subdisciplina);
      let indexPrimeiraQuestao = getNumeroPrimeiraQuestaoSubDisciplina(avaliacao, disciplina, serie, subdisciplina) - 1;

      Logger.log("gabarito-> "+ gabarito);
      Logger.log("indexPrimeiraQuestao-> "+ indexPrimeiraQuestao);
      Logger.log("indexRespostasInicioGabarito-> "+ indexRespostasInicioGabarito);
          

    //todo
      let contagemDeAcertos = folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow()).getValues().filter(function(row) {
          return row[indexRespostasProvaRef] == avaliacao
                  && row[indexRespostasDisciplina] == disciplina 
                  && row[indexRespostasIDAluno] == idAluno;
        }
      ).map(function(x) {

        let sabeEscreverONome = x[indexRespostasEscreveONome];
        let acertos = 0;
        let erros = 0;
        // Logger.log(x);
        for (var g = 0; g < gabarito.length; g++) {
          
          Logger.log("g-> "+ g);
          Logger.log("resposta do aluno-> "+ x[indexRespostasInicioGabarito + indexPrimeiraQuestao + g]);
          Logger.log("gabarito da prova-> "+ gabarito[g]);
          if (gabarito[g] == x[indexRespostasInicioGabarito + indexPrimeiraQuestao + g]){
            acertos += 1;
          } else {
            erros += 1;
          }
        }
        return [sabeEscreverONome, acertos, erros];
      });
      
      // Logger.log(contagemDeAcertos);
      // return;

      for (var x=0; x< contagemDeAcertos.length; x++) {
        if (contagemDeAcertos[x].length == 0) continue;
        
        let sabeEscreverONome = contagemDeAcertos[x][0];
        let qtdAcertos = contagemDeAcertos[x][1];
        let qtdErros = contagemDeAcertos[x][2];
        let total = qtdAcertos + qtdErros;
        let percentualDeAcertos = (qtdAcertos / total) * 100;
        let categoria = "";
        if (qtdAcertos == 0 && qtdErros == 0) {
          continue;
        } else if (percentualDeAcertos <= 25 ) {
          categoria = "MUITO BAIXO";
        } else if (percentualDeAcertos <= 50) {
          categoria = "BAIXO";
        } else if (percentualDeAcertos <= 75) {
          categoria = "MÉDIO";
        } else {
          categoria = "ALTO";
        }

        let linha = null;
        if (isUpdate === true) {
          let countRow = 1;
          folhaCorrecao.getRange('A1:AZ'+folhaCorrecao.getLastRow()).getValues().filter(function(row) {
                
                if (row[indexCorrecaoProvaRef] == avaliacao
                        && row[indexCorrecaoDisciplina] == disciplina
                        && row[indexCorrecaoIDAluno] == idAluno) {
                  
                  linha = linha == null ? countRow : linha;
                  
                  return true;
                }
                countRow = countRow + 1;
              }
            );
          
        } 
        
        if (linha == null) {
          linha = folhaCorrecao.getLastRow() + 1;
        }
        Logger.log('linha C ' + linha);              
        
        folhaCorrecao.getRange(`A${linha}`).setValue(avaliacao);
        folhaCorrecao.getRange(`B${linha}`).setValue(escola);
        folhaCorrecao.getRange(`C${linha}`).setValue(serie);
        folhaCorrecao.getRange(`D${linha}`).setValue(turma);
        folhaCorrecao.getRange(`E${linha}`).setValue(idAluno);
        folhaCorrecao.getRange(`F${linha}`).setValue(disciplina);
        folhaCorrecao.getRange(`G${linha}`).setValue(sabeEscreverONome);
        folhaCorrecao.getRange(`H${linha}`).setValue(qtdAcertos);
        folhaCorrecao.getRange(`I${linha}`).setValue(qtdErros);
        folhaCorrecao.getRange(`J${linha}`).setValue(categoria);
        folhaCorrecao.getRange(`K${linha}`).setValue(subdisciplina);
      }
    }     
            
}


function teste() {
  const values = folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow()).getValues();

  for (var index = values.length - 1; index > 1; index--) {
    let row = values[index];
    //'3','4','5'
    if ( row[indexRespostasDisciplina] == 'LÍNGUA PORTUGUESA' && ['5'].includes(row[indexRespostasSerie].charAt(0))) {          
        
          let isUpdate = row[indexRespostasSincronizadoEm] == '' ? false : true;
          
          let avaliacao = row[indexRespostasProvaRef];
          let serie = row[indexRespostasSerie];
          let disciplina = row[indexRespostasDisciplina];
          let aluno = row[indexRespostasIDAluno];

          const valuesCorrecao = folhaCorrecao.getRange('A1:AZ'+folhaCorrecao.getLastRow()).getValues();
          for (var c = 0; c < valuesCorrecao.length; c++) {

            preencherFolhaCorrecaoParaUmAluno(avaliacao, serie, disciplina, aluno, isUpdate);
          }

          if (row[indexRespostasAtualizadoEm] == '') {
            folhaRespostas.getRange(`G${index + 1}`).setValue(new Date());
          }
          folhaRespostas.getRange(`H${index + 1}`).setValue(new Date());        
    }     
  }
}

function preencherFolhaCorrecaoConceitualNivelParaUmAluno(avaliacao, serie, disciplina, idAluno, isUpdate) {
    let questoesConceituais = getQuestoesConceituais(avaliacao, serie, disciplina);
    if (questoesConceituais.length == 0) {
      return;
    }

    let escola = getEscolaPorAluno(idAluno);
    let turma = getTurmaPorAluno(idAluno);
    
      let respostasPorQuestao = folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow()).getValues().filter(function(row) {
          return row[indexRespostasProvaRef] == avaliacao
                  && row[indexRespostasDisciplina] == disciplina 
                  && row[indexRespostasIDAluno] == idAluno;
        }
      ).map(function(x) {

        let respostasDoAluno = [];
        for (var q = 0; q < questoesConceituais.length; q++) {

          let questao = questoesConceituais[q];
          let index = parseInt(questao.index);
          let subquestao = questao.subquestao;

          for (var i=0; i<subquestao.length;i++) {
            let indexSub = parseInt(subquestao[i]) - 1;

            let respostaSubQuestao = x[indexRespostasInicioGabarito + index + indexSub];

            if (['I','II','III','IV'].includes(respostaSubQuestao)) {
              respostasDoAluno.push(respostaSubQuestao);
            }
          }          
        }
        return respostasDoAluno;
      });
      
      let nivel = calcularNivelGeral(respostasPorQuestao[0]);

      let linha = null;
      if (isUpdate === true) {
        let countRow = 1;
        folhaCorrecaoConceitualNivel.getRange('A1:AZ'+folhaCorrecaoConceitualNivel.getLastRow()).getValues().filter(function(row) {
              
              if (row[indexCorrecaoConceitualNivelProvaRef] == avaliacao
                      && row[indexCorrecaoConceitualNivelDisciplina] == disciplina
                      && row[indexCorrecaoConceitualNivelIDAluno] == idAluno) {
                
                linha = linha == null ? countRow : linha;
                
                return true;
              }
              countRow = countRow + 1;
            }
          );
        
      } 
      
      if (linha == null) {
        linha = folhaCorrecaoConceitualNivel.getLastRow() + 1;
      }
      
      folhaCorrecaoConceitualNivel.getRange(`A${linha}`).setValue(avaliacao);
      folhaCorrecaoConceitualNivel.getRange(`B${linha}`).setValue(escola);
      folhaCorrecaoConceitualNivel.getRange(`C${linha}`).setValue(serie);
      folhaCorrecaoConceitualNivel.getRange(`D${linha}`).setValue(turma);
      folhaCorrecaoConceitualNivel.getRange(`E${linha}`).setValue(idAluno);
      folhaCorrecaoConceitualNivel.getRange(`F${linha}`).setValue(disciplina);
      folhaCorrecaoConceitualNivel.getRange(`G${linha}`).setValue(nivel);            
}

function calcularNivelGeral(respostas) {
  // Mapeia cada nível textual para pontos  
  var pontuacoes = {
    'I': 1,
    'II': 3,
    'III': 4,
    'IV': 5
  };
  var MAX_PONTOS_POR_SUBQUESTAO = 5;
  
  // Soma os pontos das respostas
  const pontosAlcancados = respostas.reduce((soma, resposta) => {
    return soma + (pontuacoes[resposta.toUpperCase()] ?? 0);
  }, 0);

  if (pontosAlcancados == 0) {
    return "MUITO BAIXO";
  }

  const pontuacaoMaxima = respostas.length * MAX_PONTOS_POR_SUBQUESTAO;
  const percentual = (pontosAlcancados / pontuacaoMaxima) * 100;

  // Determina classificação com base no percentual
  let classificacao;
  if (percentual <= 25) {
    classificacao = 'BAIXO';
  } else if (percentual <= 50) {
    classificacao = 'INTERMEDIÁRIO';
  } else if (percentual <= 75) {
    classificacao = 'INTERMEDIÁRIO';
  } else {
    classificacao = 'ADEQUADO';
  }

  return classificacao;

  // return {
    // percentual: percentual.toFixed(2) + '%',
    // classificacao: classificacao
  // };
}

function preencherFolhaCorrecaoPorHabilidadeParaUmAluno(avaliacao, serie, disciplina, idAluno, isUpdate) {

            let escola = getEscolaPorAluno(idAluno);
            let turma = getTurmaPorAluno(idAluno);

            let subdisciplinas = getSubdisciplinas(avaliacao, disciplina, serie);

            for (var i=0; i<subdisciplinas.length; i++){
              let subdisciplina = subdisciplinas[i];
              let gabarito = getGabaritoPorSubdisciplina(avaliacao, disciplina, serie, subdisciplina);
              let indexPrimeiraQuestao = getNumeroPrimeiraQuestaoSubDisciplina(avaliacao, disciplina, serie, subdisciplina);
              
                let habilidades = getHabilidadesPorProvaSubDisciplina(avaliacao, serie, disciplina, subdisciplina);
                
                  let gabaritoDoAluno = folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow())
                                .getValues().filter(function(row) {
                                    return row[indexRespostasProvaRef] == avaliacao
                                            && row[indexRespostasDisciplina] == disciplina 
                                            && row[indexRespostasIDAluno] == idAluno;
                                  }
                                );      
                  
                  for (var x=0; x< gabaritoDoAluno.length; x++) {
                    
                      let respostaAluno = gabaritoDoAluno[x];

                      let mapHabilidades = {};
                      for (var g = 0; g < gabarito.length; g++) {
                        let habilidade = habilidades[g];
                        if (!(habilidade in mapHabilidades)) {
                          mapHabilidades[habilidade] = {'acertos': 0, 'erros': 0};
                        }

                        if (gabarito[g] == respostaAluno[indexRespostasInicioGabarito + indexPrimeiraQuestao + g]) {
                          mapHabilidades[habilidade]['acertos'] += 1;
                        } else {
                          mapHabilidades[habilidade]['erros'] += 1;
                        }
                      }
                    
                      for (const h in mapHabilidades) {
                        const acertosErros = mapHabilidades[h];

                        let qtdAcertos = acertosErros['acertos'];
                        let qtdErros = acertosErros['erros'];
                        let total = qtdAcertos + qtdErros;
                        let percentualDeAcertos = (qtdAcertos / total) * 100;
                        
                        let categoria = "";

                        if (qtdAcertos == 0 && qtdErros == 0) {
                          continue;
                      } else if (percentualDeAcertos <= 25 ) {
                          categoria = "MUITO BAIXO";
                        } else if (percentualDeAcertos <= 50) {
                          categoria = "BAIXO";
                        } else if (percentualDeAcertos <= 75) {
                          categoria = "MÉDIO";
                        } else {
                          categoria = "ALTO";
                        }

                          let linha = null;
                            if (isUpdate === true) {
                              let countRow = 1;
                              folhaCorrecaoPorHabilidade.getRange('A1:AZ'+folhaCorrecaoPorHabilidade.getLastRow()).getValues().filter(function(row) {
                                    
                                    if (row[indexCorrecaoPorHabilidadeProvaRef] == avaliacao
                                            && row[indexCorrecaoPorHabilidadeDisciplina] == disciplina
                                            && row[indexCorrecaoPorHabilidadeIDAluno] == idAluno
                                            && row[indexCorrecaoPorHabilidadeSubDisciplina] == subdisciplina) {
                                      
                                      linha = linha == null ? countRow : linha;
                                      
                                      return true;
                                    }
                                    countRow = countRow + 1;
                                  }
                                );
                              
                            } 
                            
                            if (linha == null) {
                              linha = folhaCorrecaoPorHabilidade.getLastRow() + 1;
                            }

                            folhaCorrecaoPorHabilidade.getRange(`A${linha}:K${linha}`)
                                                  .setValues([[avaliacao, 
                                                              escola,
                                                              serie,
                                                              turma,
                                                              idAluno,
                                                              disciplina,
                                                              h,
                                                              qtdAcertos,
                                                              qtdErros,
                                                              categoria,
                                                              subdisciplina]]);

                      }         
                  }
            }
}

function removerRespostas() {
    let avaliacao = 1;
    let serie = '7º ANO';
    let disciplina = 'MATEMÁTICA';

    const escolas = folhaConfiguracao.getRange('A2:Z'+folhaConfiguracao.getLastRow()).getValues().filter(function(row){
        return row[indexConfigINEP].toString().length > 0;
      }
    ).map(function (e) {
      return e[indexConfigEscola]
    });;

    let linha = 2;

    for (var e=0; e<escolas.length; e++){
      let escola = escolas[e];
      
      let turmas = getTurmas(escola, serie);
      for (var t=0; t< turmas.length; t++){
        let turma = turmas[t];

        const alunosID = folhaAlunos.getRange('A1:Z'+folhaAlunos.getLastRow()).getValues().filter(function(row) {
            return row[indexAlunosProvaRef] == avaliacao
                    && row[indexAlunosEscola] == escola 
                    && row[indexAlunosSerie].toString() == serie
                    && row[indexAlunosTurma].toString() == turma;
          }
        ).map(function(e){
          return e[indexAlunosID]
        });
        

            
        const respostasIDAlunos = folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow()).getValues().filter(function(row) {
            return row[indexRespostasProvaRef] == avaliacao
                    && row[indexRespostasDisciplina] == disciplina 
                    && alunosID.includes(row[indexRespostasIDAluno]);
          }
        ).map(function(e){
          return e[indexRespostasIDAluno]
        });

            var unique = respostasIDAlunos.filter(onlyUnique);
            
            folhaQuantitativo.getRange(`A${linha}`).setValue(escola);
            folhaQuantitativo.getRange(`B${linha}`).setValue(serie);
            folhaQuantitativo.getRange(`C${linha}`).setValue(turma);
            folhaQuantitativo.getRange(`D${linha}`).setValue(disciplina);
            folhaQuantitativo.getRange(`E${linha}`).setValue(alunosID.length);
            folhaQuantitativo.getRange(`F${linha}`).setValue(unique.length);

            linha++;
           
        }
      
    }
}

function syncResults(row, index) {
    
  if ( row[indexRespostasAtualizadoEm] == '' || row[indexRespostasSincronizadoEm] == '' 
            || new Date(row[indexRespostasAtualizadoEm]) > new Date(row[indexRespostasSincronizadoEm])) {          
        
        let isUpdate = row[indexRespostasSincronizadoEm] == '' ? false : true;
        
        let avaliacao = row[indexRespostasProvaRef];
        let serie = row[indexRespostasSerie];
        let disciplina = row[indexRespostasDisciplina];
        let aluno = row[indexRespostasIDAluno];
        
        try {
            preencherFolhaCorrecaoParaUmAluno(avaliacao, serie, disciplina, aluno, isUpdate);
            preencherFolhaCorrecaoPorHabilidadeParaUmAluno(avaliacao, serie, disciplina, aluno, isUpdate);
            preencherFolhaCorrecaoConceitualNivelParaUmAluno(avaliacao, serie, disciplina, aluno, isUpdate);

            if (row[indexRespostasAtualizadoEm] == '') {
              folhaRespostas.getRange(`G${index + 1}`).setValue(new Date());
            }
            folhaRespostas.getRange(`H${index + 1}`).setValue(new Date());        
        } catch (e) {
            // opcional: logar o erro em algum lugar
            Logger.log("Erro: " + e.message);
            Logger.log("Stack: " + e.stack);
            Logger.log("Aluno: " + aluno);
            Logger.log("Erro ao preencher correções para aluno" + aluno + ": " + e);
        }
  }
}

function syncResultsParaUmAluno(avaliacao, serie, disciplina, aluno) {
    try {
        preencherFolhaCorrecaoParaUmAluno(avaliacao, serie, disciplina, aluno, true);
        preencherFolhaCorrecaoPorHabilidadeParaUmAluno(avaliacao, serie, disciplina, aluno, true);
        preencherFolhaCorrecaoConceitualNivelParaUmAluno(avaliacao, serie, disciplina, aluno, true);
    } catch (e) {
        // opcional: logar o erro em algum lugar
        Logger.log("Erro: " + e.message);
        Logger.log("Stack: " + e.stack);
        Logger.log("Aluno: " + aluno);
        Logger.log("Erro ao preencher correção para aluno " + aluno + ": " + e);
    }
}

function syncResultsInitToEnd() {
  
  const values = folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow()).getValues();

  for (var index =1; index< values.length; index++){
    let row = values[index];
    syncResults(row, index);
  }
}

function syncResultsEndToInit() {
  
  const values = folhaRespostas.getRange('A1:AZ'+folhaRespostas.getLastRow()).getValues();

  for (var index = values.length - 1; index > 1; index--) {
    let row = values[index];
    syncResults(row, index);    
  }
}

/** */
function addSerieDoAluno() {
  const values = folhaCorrecaoPorHabilidade.getRange('A1:Z'+folhaCorrecaoPorHabilidade.getLastRow()).getValues();

    for (var i = 1; i < values.length; i++) {        
        if (values[i][indexCorrecaoPorHabilidadeSerie] != '') {
          console.log('pulando linha ' + (i+1));
          continue;
        }
        let serie = getSeriePorAluno(values[i][indexCorrecaoPorHabilidadeIDAluno]);
        folhaCorrecaoPorHabilidade.getRange(`C${i+1}`).setValue(serie);
    }
}

function addEscolaDoAluno() {
  const values = folhaCorrecaoPorHabilidade.getRange('A1:BB'+folhaCorrecaoPorHabilidade.getLastRow()).getValues();

    for (var i = 1; i < values.length; i++) { 
        if (values[i][indexCorrecaoPorHabilidadeEscola] != undefined && values[i][indexCorrecaoPorHabilidadeEscola] != '') {
          continue;
        }
        
        let escola = getEscolaPorAluno(values[i][indexCorrecaoPorHabilidadeIDAluno]);
        folhaCorrecaoPorHabilidade.getRange(`B${i+1}`).setValue(escola);
    }
}

function addTurmaDoAluno() {
  const values = folhaCorrecaoPorHabilidade.getRange('A1:Z'+folhaCorrecaoPorHabilidade.getLastRow()).getValues();

    for (var i = 1; i < values.length; i++) {        
        if (values[i][indexCorrecaoPorHabilidadeTurma] != undefined && values[i][indexCorrecaoPorHabilidadeTurma] != '') {
          console.log('pulando linha ' + (i+1) + ": " + values[i][indexCorrecaoPorHabilidadeTurma]);
          continue;
        }
        
        let turma = getTurmaPorAluno(values[i][indexCorrecaoPorHabilidadeIDAluno]);
        folhaCorrecaoPorHabilidade.getRange(`D${i+1}`).setValue(turma);
    }
}
