/**
 * Testes unitários para UnsavedChangesGuard - Versão Node.js
 *
 * Executa verificações básicas da estrutura do código.
 * Para executar: node spec/javascripts/unsaved_changes_guard_node_spec.js
 */

const fs = require('fs');
const path = require('path');

let testsPassed = 0;
let testsFailed = 0;

function assert(condition, message) {
  if (condition) {
    testsPassed++;
    console.log(`✓ PASS: ${message}`);
  } else {
    testsFailed++;
    console.log(`✗ FAIL: ${message}`);
  }
}

function assertContains(text, pattern, message) {
  const condition = text.includes(pattern);
  if (!condition) {
    message = `${message} (pattern "${pattern}" not found)`;
  }
  assert(condition, message);
}

function runTests() {
  console.log('=== Testes de Estrutura do UnsavedChangesGuard ===\n');

  const guardPath = path.join(__dirname, '../../app/assets/javascripts/unsaved_changes_guard.js');
  const guardCode = fs.readFileSync(guardPath, 'utf8');

  // Test 1: Arquivo existe e não está vazio
  assert(guardCode.length > 0, 'Arquivo unsaved_changes_guard.js existe e não está vazio');

  // Test 2: Define o módulo UnsavedChangesGuard
  assertContains(guardCode, 'UnsavedChangesGuard', 'Define o módulo UnsavedChangesGuard');

  // Test 3: Exporta para global
  assertContains(guardCode, 'global.UnsavedChangesGuard', 'Exporta módulo para escopo global');

  // Test 4: Tem método watch
  assertContains(guardCode, 'watch:', 'Define método watch');

  // Test 5: Tem array de instâncias
  assertContains(guardCode, 'instances:', 'Define array de instâncias');

  // Test 6: Tem opções padrão
  assertContains(guardCode, 'defaultOptions:', 'Define opções padrão');

  // Test 7: Tem título padrão em português
  assertContains(guardCode, 'Deseja salvar', 'Título padrão está em português');

  // Test 8: Tem botão Salvar
  assertContains(guardCode, 'Salvar', 'Botão de salvar está presente');

  // Test 9: Tem botão Sair sem salvar
  assertContains(guardCode, 'Sair sem salvar', 'Botão de sair sem salvar está presente');

  // Test 10: Usa bootbox
  assertContains(guardCode, 'bootbox.confirm', 'Usa bootbox.confirm para modal');

  // Test 11: Usa beforeunload
  assertContains(guardCode, 'beforeunload', 'Implementa beforeunload para fechar aba');

  // Test 12: Tem método markAsChanged
  assertContains(guardCode, 'markAsChanged', 'Define método markAsChanged');

  // Test 13: Tem método markAsSaved
  assertContains(guardCode, 'markAsSaved', 'Define método markAsSaved');

  // Test 14: Tem método hasChanges
  assertContains(guardCode, 'hasChanges', 'Define método hasChanges');

  // Test 15: Tem método reset
  assertContains(guardCode, 'reset:', 'Define método reset');

  // Test 16: Tem método destroy
  assertContains(guardCode, 'destroy:', 'Define método destroy');

  // Test 17: Tem método destroyAll
  assertContains(guardCode, 'destroyAll:', 'Define método destroyAll');

  // Test 18: Ignora campos select2-search
  assertContains(guardCode, 'select2-search', 'Ignora campos de busca do Select2');

  // Test 19: Detecta mudanças em checkboxes
  assertContains(guardCode, ':checkbox', 'Detecta mudanças em checkboxes');

  // Test 20: Detecta mudanças em radio buttons
  assertContains(guardCode, ':radio', 'Detecta mudanças em radio buttons');

  // Test 21: Suporta Summernote
  assertContains(guardCode, 'summernote.change', 'Suporta eventos do Summernote');

  // Test 22: Suporta Cocoon
  assertContains(guardCode, 'cocoon:', 'Suporta eventos do Cocoon');

  // Test 23: Usa IIFE para escopo
  assertContains(guardCode, '(function', 'Usa IIFE para encapsulamento');

  // Test 24: Usa strict mode
  assertContains(guardCode, "'use strict'", 'Usa strict mode');

  console.log('\n=== Verificando Integrações ===\n');

  const integrationFiles = [
    { file: 'app/assets/javascripts/views/discipline_content_records/form.js', name: 'discipline_content_records' },
    { file: 'app/assets/javascripts/views/knowledge_area_content_records/form.js', name: 'knowledge_area_content_records' },
    { file: 'app/assets/javascripts/views/observation_diary_records/form.js', name: 'observation_diary_records' },
    { file: 'app/assets/javascripts/views/discipline_lesson_plans/form.js', name: 'discipline_lesson_plans' },
    { file: 'app/assets/javascripts/views/knowledge_area_lesson_plans/form.js', name: 'knowledge_area_lesson_plans' },
    { file: 'app/assets/javascripts/views/discipline_teaching_plans/form.js', name: 'discipline_teaching_plans' },
    { file: 'app/assets/javascripts/views/knowledge_area_teaching_plans/form.js', name: 'knowledge_area_teaching_plans' },
    { file: 'app/assets/javascripts/views/school_term_recovery_diary_records/form.js', name: 'school_term_recovery_diary_records' },
    { file: 'app/assets/javascripts/views/avaliation_recovery_diary_records/form.js', name: 'avaliation_recovery_diary_records' },
    { file: 'app/assets/javascripts/views/final_recovery_diary_records/form.js', name: 'final_recovery_diary_records' },
    { file: 'app/assets/javascripts/views/aee_individual_plans/form.js', name: 'aee_individual_plans (PEI)' },
    { file: 'app/assets/javascripts/views/aee_case_studies/form.js', name: 'aee_case_studies' },
    { file: 'app/assets/javascripts/views/aee_attendance_records/form.js', name: 'aee_attendance_records' },
    { file: 'app/assets/javascripts/views/conceptual_exams/form.js', name: 'conceptual_exams' },
    { file: 'app/assets/javascripts/views/descriptive_exams/student_fields.js', name: 'descriptive_exams' },
    { file: 'app/assets/javascripts/views/complementary_exams/form.js', name: 'complementary_exams' },
    { file: 'app/assets/javascripts/views/transfer_notes/form.js', name: 'transfer_notes' },
    { file: 'app/assets/javascripts/views/daily_frequencies/edit_multiple.js', name: 'daily_frequencies' },
    { file: 'app/assets/javascripts/views/daily_frequencies_in_batchs/create_or_update_multiple.js', name: 'daily_frequencies_in_batchs' }
  ];

  integrationFiles.forEach(({ file, name }) => {
    const fullPath = path.join(__dirname, '../../', file);
    try {
      const content = fs.readFileSync(fullPath, 'utf8');
      assertContains(content, 'UnsavedChangesGuard', `${name} integra UnsavedChangesGuard`);
    } catch (e) {
      assert(false, `${name} - arquivo não encontrado: ${file}`);
    }
  });

  console.log('\n=== Verificando application.js.erb ===\n');

  const applicationPath = path.join(__dirname, '../../app/assets/javascripts/application.js.erb');
  const applicationCode = fs.readFileSync(applicationPath, 'utf8');
  assertContains(applicationCode, 'unsaved_changes_guard', 'application.js.erb requer unsaved_changes_guard');

  // Resumo
  console.log('\n=== Resumo dos Testes ===');
  console.log(`✓ Passou: ${testsPassed}`);
  if (testsFailed > 0) {
    console.log(`✗ Falhou: ${testsFailed}`);
    process.exit(1);
  } else {
    console.log('Todos os testes passaram!');
    process.exit(0);
  }
}

runTests();
