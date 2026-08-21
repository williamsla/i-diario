# frozen_string_literal: true

FactoryGirl.define do
  factory :aee_case_study do
    unity
    classroom { create(:classroom, unity: unity) }
    student
    teacher
    user
    school_calendar { create(:school_calendar, :with_one_step, unity: unity) }

    year { Date.current.year }
    grade_stage 'AEE'
    age '6 anos'
    identification 'Deficiência intelectual'
    modality 'Atendimento Educacional Especializado'
    individual_demands 'Demandas individuais e barreiras identificadas'
    barriers_and_context 'Análise das barreiras e do contexto escolar'
    potentialities_and_support 'Potencialidades e demandas de apoio'
    accessibility_strategies 'Estratégias e recursos de acessibilidade'
    final_considerations 'Considerações finais do estudo'
    specialized_teacher_name { teacher.name }
    document_date { Date.current }
  end
end
