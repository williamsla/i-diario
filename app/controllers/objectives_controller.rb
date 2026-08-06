class ObjectivesController < ApplicationController
  respond_to :json

  def index
    @objectives = Objective.none
    if params[:fetch_for_discipline_records]
      teacher = current_teacher
      classroom = Classroom.find(params[:classroom_id])
      discipline = Discipline.find(params[:discipline_id])
      date = params[:date]
      return unless teacher && classroom && discipline && date
      @objectives = ContentsForDisciplineRecordFetcher.new(
        teacher, classroom, discipline, date, params[:student_id]
      ).fetch_objectives
    elsif params[:fetch_for_knowledge_area_records]
      teacher = current_teacher
      classroom = Classroom.find(params[:classroom_id])
      knowledge_areas = KnowledgeArea.find(params[:knowledge_area_ids])
      date = params[:date]
      return unless teacher && classroom && knowledge_areas && date
      @objectives = ContentsForKnowledgeAreaRecordFetcher.new(
        teacher, classroom, knowledge_areas, date, params[:student_id]
      ).fetch_objectives
    elsif !params[:merge_objectives_by_code] || params[:filter][:by_description]
      @objectives = apply_scopes(Objective)
    elsif params[:filter][:start_with_description]
      @objectives = Content.start_with_description(params[:filter][:start_with_description])
    end

    if params[:merge_objectives_by_code]
      @objectives = @objectives + ObjectivesToContentFetcher.fetch(params[:merge_objectives_by_code])
      @objectives = @objectives.map(&:description).uniq.sort.map{|description| { description: description }}
    end

    respond_with(@objectives)
  end
end
