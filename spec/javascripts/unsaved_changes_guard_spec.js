/**
 * Testes unitários para UnsavedChangesGuard
 *
 * Estes testes podem ser executados no browser através do console
 * após carregar o módulo UnsavedChangesGuard.
 *
 * Para executar:
 *   1. Abra qualquer página do i-Diário no navegador
 *   2. Abra o console do desenvolvedor (F12)
 *   3. Cole este código e execute
 */

(function() {
  'use strict';

  var testResults = {
    passed: 0,
    failed: 0,
    tests: []
  };

  function assert(condition, message) {
    if (condition) {
      testResults.passed++;
      testResults.tests.push({ status: 'PASS', message: message });
      console.log('%c✓ PASS: ' + message, 'color: green');
    } else {
      testResults.failed++;
      testResults.tests.push({ status: 'FAIL', message: message });
      console.log('%c✗ FAIL: ' + message, 'color: red');
    }
  }

  function assertEqual(actual, expected, message) {
    var condition = actual === expected;
    if (!condition) {
      message = message + ' (expected: ' + expected + ', got: ' + actual + ')';
    }
    assert(condition, message);
  }

  function createTestForm() {
    var $form = $('<form id="test-form">' +
      '<input type="text" name="text_field" id="text_field" value="initial">' +
      '<textarea name="textarea_field" id="textarea_field">initial text</textarea>' +
      '<select name="select_field" id="select_field">' +
      '  <option value="1">Option 1</option>' +
      '  <option value="2" selected>Option 2</option>' +
      '</select>' +
      '<input type="checkbox" name="checkbox_field" id="checkbox_field">' +
      '<input type="submit" value="Salvar">' +
      '</form>');
    $('body').append($form);
    return $form;
  }

  function removeTestForm() {
    $('#test-form').remove();
  }

  function runTests() {
    console.log('%c=== Executando testes do UnsavedChangesGuard ===', 'font-weight: bold; font-size: 14px');

    // Test 1: Módulo existe
    assert(typeof UnsavedChangesGuard !== 'undefined', 'Módulo UnsavedChangesGuard está definido');

    // Test 2: Método watch existe
    assert(typeof UnsavedChangesGuard.watch === 'function', 'Método watch está disponível');

    // Test 3: Método destroyAll existe
    assert(typeof UnsavedChangesGuard.destroyAll === 'function', 'Método destroyAll está disponível');

    // Test 4: Criar instância retorna objeto válido
    var $form = createTestForm();
    var guard = UnsavedChangesGuard.watch('#test-form');
    assert(guard !== null, 'watch() retorna instância válida');

    // Test 5: Instância tem métodos esperados
    assert(typeof guard.markAsChanged === 'function', 'Instância tem método markAsChanged');
    assert(typeof guard.markAsSaved === 'function', 'Instância tem método markAsSaved');
    assert(typeof guard.hasChanges === 'function', 'Instância tem método hasChanges');
    assert(typeof guard.reset === 'function', 'Instância tem método reset');
    assert(typeof guard.destroy === 'function', 'Instância tem método destroy');

    // Test 6: Inicialmente não há mudanças
    assertEqual(guard.hasChanges(), false, 'Inicialmente hasChanges() retorna false');

    // Test 7: Marcar como alterado funciona
    guard.markAsChanged();
    assertEqual(guard.hasChanges(), true, 'Após markAsChanged(), hasChanges() retorna true');

    // Test 8: Reset funciona
    guard.reset();
    assertEqual(guard.hasChanges(), false, 'Após reset(), hasChanges() retorna false');

    // Test 9: Detecta mudança em input text
    guard.reset();
    $('#text_field').val('modified').trigger('change');
    assertEqual(guard.hasChanges(), true, 'Detecta mudança em input text');

    // Test 10: Detecta mudança em textarea
    guard.reset();
    $('#textarea_field').val('modified text').trigger('change');
    assertEqual(guard.hasChanges(), true, 'Detecta mudança em textarea');

    // Test 11: Detecta mudança em select
    guard.reset();
    $('#select_field').val('1').trigger('change');
    assertEqual(guard.hasChanges(), true, 'Detecta mudança em select');

    // Test 12: Detecta mudança em checkbox
    guard.reset();
    $('#checkbox_field').prop('checked', true).trigger('change');
    assertEqual(guard.hasChanges(), true, 'Detecta mudança em checkbox');

    // Test 13: Destroy remove instância
    var instanceCount = UnsavedChangesGuard.instances.length;
    guard.destroy();
    assertEqual(UnsavedChangesGuard.instances.length, instanceCount - 1, 'destroy() remove instância do array');

    // Cleanup
    removeTestForm();

    // Test 14: Watch em formulário inexistente retorna null
    var nullGuard = UnsavedChangesGuard.watch('#nonexistent-form');
    assertEqual(nullGuard, null, 'watch() em formulário inexistente retorna null');

    // Test 15: Opções personalizadas são aceitas
    $form = createTestForm();
    guard = UnsavedChangesGuard.watch('#test-form', {
      title: 'Custom Title',
      message: 'Custom Message'
    });
    assert(guard !== null, 'watch() aceita opções personalizadas');
    guard.destroy();
    removeTestForm();

    // Test 16: DestroyAll limpa todas as instâncias
    $form = createTestForm();
    UnsavedChangesGuard.watch('#test-form');
    UnsavedChangesGuard.destroyAll();
    assertEqual(UnsavedChangesGuard.instances.length, 0, 'destroyAll() limpa todas as instâncias');
    removeTestForm();

    // Resumo
    console.log('%c=== Resumo dos Testes ===', 'font-weight: bold; font-size: 14px');
    console.log('%c✓ Passou: ' + testResults.passed, 'color: green; font-weight: bold');
    if (testResults.failed > 0) {
      console.log('%c✗ Falhou: ' + testResults.failed, 'color: red; font-weight: bold');
    }

    return testResults;
  }

  // Exportar para uso global
  window.UnsavedChangesGuardTests = {
    run: runTests,
    results: testResults
  };

  // Auto-executar se jQuery e UnsavedChangesGuard estiverem disponíveis
  if (typeof jQuery !== 'undefined' && typeof UnsavedChangesGuard !== 'undefined') {
    console.log('Para executar os testes, chame: UnsavedChangesGuardTests.run()');
  } else {
    console.warn('jQuery ou UnsavedChangesGuard não disponível. Carregue os scripts primeiro.');
  }
})();
