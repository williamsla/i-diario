# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FeaturesAccessLevels, type: :service do
  it 'offers the access report to administrator and employee profiles' do
    expect(described_class.administrator_features).to include(:user_access_reports)
    expect(described_class.employee_features).to include(:user_access_reports)
    expect(described_class.teacher_features).not_to include(:user_access_reports)
    expect(described_class.student_features).not_to include(:user_access_reports)
    expect(described_class.parent_features).not_to include(:user_access_reports)
  end
end
