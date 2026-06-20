FactoryGirl.define do
  factory :school_calendar_event_batch do
    year { Date.current.year }
    description { Faker::Lorem.unique.sentence }
    legend { ('A'..'Z').to_a.delete_if { |legend| ['F', 'N'].include?(legend) }[rand(24)] }
    start_date { Date.current.beginning_of_year }
    end_date { Date.current.end_of_year }
    event_type { EventTypes::EXTRA_SCHOOL }
    periods { Periods.list }
    batch_status { BatchStatus::STARTED }
  end
end
