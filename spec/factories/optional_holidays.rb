# frozen_string_literal: true

FactoryGirl.define do
  factory :optional_holiday do
    user
    year { Date.current.year }
    holiday_date { Date.current }
    description { 'Ponto facultativo - decreto municipal' }
    periods { %w[1 2 3] }
    makeup_scope { OptionalHolidayMakeupScope::MUNICIPAL }
  end
end
