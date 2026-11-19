# frozen_string_literal: true

FactoryGirl.define do
  factory :optional_holiday_course_makeup do
    optional_holiday
    course
    user
    make_up_date { Date.current + 2.days }
  end
end
