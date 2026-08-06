FactoryGirl.define do
  factory :knowledge_area_content_record do
    content_record factory: [:content_record, :with_contents]

    transient do
      knowledge_areas { [create(:knowledge_area)] }
    end

    after(:build) do |knowledge_area_content_record, evaluator|
      knowledge_area_content_record.knowledge_areas = evaluator.knowledge_areas
    end
  end
end
