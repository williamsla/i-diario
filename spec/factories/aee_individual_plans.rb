# frozen_string_literal: true

FactoryGirl.define do
  factory :aee_individual_plan do
    unity
    classroom { create(:classroom, unity: unity) }
    student
    teacher
    user
    school_calendar { create(:school_calendar, :with_one_step, unity: unity) }

    year { Date.current.year }
    start_on { Date.current }
    age '6 anos'
    characteristics 'Características e potencialidades do estudante'
    psychomotor_skills 'Habilidades psicomotoras'
    cognitive_skills 'Habilidades cognitivas'
    socioemotional_skills 'Habilidades socioafetivas'
    linguistic_skills 'Habilidades linguísticas'
    identified_difficulties 'Dificuldades identificadas'
    goals 'Objetivos a serem alcançados'
    resources 'Recursos didáticos'
    strategies 'Estratégias pedagógicas'
    monitoring 'Síntese do monitoramento'
    short_term_goals 'Objetivos de curto prazo'
    long_term_goals 'Objetivos de longo prazo'
    final_considerations 'Considerações finais'
    specialized_teacher_name { teacher.name }
    document_date { Date.current }
  end
end
