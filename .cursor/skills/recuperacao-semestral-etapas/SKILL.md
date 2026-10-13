---
name: recuperacao-semestral-etapas
description: >-
  Preserva o filtro de etapas na recuperação semestral/específica do i-Diário.
  Use ao editar school_term_recovery_diary_records, Select2StepSpecificRecoveryInput,
  fetch_step de recuperação, form.js de recuperação de etapas, ou ao trabalhar com
  semestral_recovery / recovery_exam_rules.
---

# Recuperação semestral — etapas filtradas

## Problema que esta skill evita

O formulário de recuperação de etapas/semestral deve mostrar **só** as etapas finais de cada `recovery_exam_rule` (ex.: bimestres 2 e 4). Em abril/2026 o `initializeFixedClassroom()` passou a chamar `fetch_step` no load e o endpoint devolvia **todas** as etapas, apagando o filtro do HTML.

## Regras ao alterar código

1. Manter `Select2StepSpecificRecoveryInput` alinhado com o filtro do controller.
2. Em `SchoolTermRecoveryDiaryRecordsController#fetch_step`, filtrar **somente** se `params[:specific_recovery]` for verdadeiro — a rota é compartilhada com complementary exams.
3. Em `school_term_recovery_diary_records/form.js`, `getStep()` deve enviar `specific_recovery: true`.
4. Qualquer AJAX que rehydrate o select de etapa no load ou no change da turma deve preservar esse filtro.

## Filtro canônico

```ruby
exam_rule.recovery_exam_rules.any? do |recovery_specific|
  recovery_specific.steps.last.eql?(step.to_number)
end
```

## Verificação rápida

- Turma com recuperação específica: select sem 1º/3º (quando a regra cobre só 2º/4º).
- Complementary exams: continua listando todas as etapas (sem `specific_recovery`).
