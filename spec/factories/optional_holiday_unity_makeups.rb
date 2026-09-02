# frozen_string_literal: true

FactoryGirl.define do
  factory :optional_holiday_unity_makeup do
    optional_holiday
    unity
    user
    make_up_date { Date.current + 1.day }
  end
end
