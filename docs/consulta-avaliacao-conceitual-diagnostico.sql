-- Diagnóstico: avaliação conceitual não aparece no Preencher/Editar
-- Caso: Creusa, 2º ANO A, 1ª Unidade, ESCOLA MUNICIPAL JOSÉ GUILHERME DA SILVA (Canindé)
-- Ajuste os filtros ILIKE conforme o ambiente.

-- 1) Localizar turma, escola e professora
SELECT
  c.id AS classroom_id,
  c.description AS turma,
  u.id AS unity_id,
  u.name AS escola,
  t.id AS teacher_id,
  t.name AS professora
FROM classrooms c
JOIN unities u ON u.id = c.unity_id
LEFT JOIN teacher_discipline_classrooms tdc ON tdc.classroom_id = c.id
LEFT JOIN teachers t ON t.id = tdc.teacher_id
WHERE u.name ILIKE '%JOSÉ GUILHERME%'
  AND c.description ILIKE '%2%ANO%A%'
  AND t.name ILIKE '%CREUSA%'
GROUP BY c.id, c.description, u.id, u.name, t.id, t.name;

-- 2) Vínculos da professora na turma (ano do calendário da turma)
-- Substitua :classroom_id e :teacher_id pelos IDs da consulta anterior.
/*
SELECT
  tdc.id,
  tdc.year,
  d.id AS discipline_id,
  d.description AS disciplina
FROM teacher_discipline_classrooms tdc
JOIN disciplines d ON d.id = tdc.discipline_id
WHERE tdc.classroom_id = :classroom_id
  AND tdc.teacher_id = :teacher_id
ORDER BY d.description;
*/

-- 3) Lançamentos conceituais da 1ª unidade (inclui descartados)
-- step_number = 1 costuma ser a 1ª Unidade (confirme no calendário da escola).
/*
SELECT
  ce.id AS conceptual_exam_id,
  s.name AS aluno,
  ce.step_number,
  ce.recorded_at,
  ce.discarded_at,
  ce.created_at,
  ce.updated_at,
  d.description AS disciplina,
  cev.value AS conceito
FROM conceptual_exams ce
JOIN students s ON s.id = ce.student_id
LEFT JOIN conceptual_exam_values cev ON cev.conceptual_exam_id = ce.id
LEFT JOIN disciplines d ON d.id = cev.discipline_id
WHERE ce.classroom_id = :classroom_id
  AND ce.step_number = 1
ORDER BY s.name, d.description;
*/

-- 4) Resumo: alunos com/sem nota e exames descartados
/*
SELECT
  COUNT(DISTINCT ce.student_id) AS alunos_com_exame,
  COUNT(DISTINCT ce.student_id) FILTER (WHERE ce.discarded_at IS NOT NULL) AS exames_descartados,
  COUNT(cev.id) AS total_valores,
  COUNT(cev.id) FILTER (WHERE cev.value IS NOT NULL AND cev.value::text <> '') AS valores_preenchidos
FROM conceptual_exams ce
LEFT JOIN conceptual_exam_values cev ON cev.conceptual_exam_id = ce.id
WHERE ce.classroom_id = :classroom_id
  AND ce.step_number = 1;
*/

-- 5) Duplicidade (dois exames para o mesmo aluno na mesma etapa)
/*
SELECT
  ce.student_id,
  s.name,
  COUNT(*) AS qtd_exames,
  ARRAY_AGG(ce.id ORDER BY ce.id) AS exam_ids,
  ARRAY_AGG(ce.discarded_at::text ORDER BY ce.id) AS discarded_at
FROM conceptual_exams ce
JOIN students s ON s.id = ce.student_id
WHERE ce.classroom_id = :classroom_id
  AND ce.step_number = 1
GROUP BY ce.student_id, s.name
HAVING COUNT(*) > 1;
*/

-- 6) Comparar com o que o relatório usaria (exames ativos, step_number)
/*
SELECT
  s.name AS aluno,
  STRING_AGG(DISTINCT d.description || '=' || COALESCE(cev.value::text, '-'), ', ' ORDER BY d.description) AS conceitos
FROM conceptual_exams ce
JOIN students s ON s.id = ce.student_id
JOIN conceptual_exam_values cev ON cev.conceptual_exam_id = ce.id
JOIN disciplines d ON d.id = cev.discipline_id
WHERE ce.classroom_id = :classroom_id
  AND ce.step_number = 1
  AND ce.discarded_at IS NULL
GROUP BY s.id, s.name
ORDER BY s.name;
*/
