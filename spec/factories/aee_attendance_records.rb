# frozen_string_literal: true

FactoryGirl.define do
  factory :aee_attendance_record do
    unity
    classroom { create(:classroom, unity: unity) }
    student
    teacher
    user
    school_calendar { create(:school_calendar, :with_one_step, unity: unity) }

    year { Date.current.year }
    record_date { Date.current }
    duration '50 minutos'
    session_focus 'Linguagem e comunicação'
    session_objectives 'Ampliar a comunicação funcional'
    activities_developed 'Atividades de comunicação alternativa desenvolvidas na sessão'
    student_response 'Participou com apoio do professor'
    next_steps 'Retomar o vocabulário na próxima sessão'
  end
end
