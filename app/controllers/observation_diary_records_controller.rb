class ObservationDiaryRecordsController < ApplicationController
  has_scope :page, default: 1
  has_scope :per, default: 10

  before_action :require_current_classroom
  before_action :require_current_teacher
  before_action :require_allow_to_modify_prev_years, only: [:create, :update, :destroy]

  def index
    current_discipline = fetch_current_discipline
    unity_ids = unities.map(&:id)
    unity_ids = [current_unity.id] if unity_ids.blank? && current_unity.present?

    relation = ObservationDiaryRecord
      .includes(:discipline, classroom: :unity)
      .by_unity(unity_ids)
      .ordered

    if current_user.teacher?
      relation = relation.by_discipline([current_discipline&.id, nil])
    end

    @observation_diary_records = apply_scopes(relation)
    @students = fetch_students_with_observation_diary_records
  end

  def show
    @observation_diary_record = ObservationDiaryRecord.find(params[:id]).localized

    @observation_record_report_form = ObservationRecordReportForm.new(
      teacher_id: @observation_diary_record.teacher.id,
      discipline_id: @observation_diary_record.discipline_id || 'all',
      unity_id: @observation_diary_record.unity_id,
      classroom_id: @observation_diary_record.classroom.id,
      start_at: @observation_diary_record.date,
      end_at: @observation_diary_record.date
    ).localized

    if @observation_record_report_form.valid?
      observation_record_report = ObservationRecordReport.new(
        current_entity_configuration,
        @observation_record_report_form
      ).build
      send_pdf(t("routes.observation_record"), observation_record_report.render)
    else
      render @observation_diary_records
    end
  end

  def new
    @observation_diary_record = ObservationDiaryRecord.new.localized
    @observation_diary_record.school_calendar_id = current_school_calendar.id
    @observation_diary_record.teacher = current_teacher
    @observation_diary_record.date = Time.zone.today
    @observation_diary_record.active_search = true if general_record?
    set_discipline_form_state
  end

  def create
    set_discipline_form_state

    attributes = resource_params.to_unsafe_h
    attributes = attributes.except('discipline_id', :discipline_id) if @general_record

    @observation_diary_record = ObservationDiaryRecord.new(attributes)
    @observation_diary_record.teacher = current_teacher
    @observation_diary_record.discipline_id = nil if @general_record
    @observation_diary_record.requires_discipline = !@general_record

    authorize @observation_diary_record

    if @observation_diary_record.save
      respond_with @observation_diary_record, location: observation_diary_records_path
    else
      begin
        resource_params[:date].to_date
      rescue ArgumentError
        @observation_diary_record.date = ''
      end
      render :new
    end
  end

  def edit
    @observation_diary_record = ObservationDiaryRecord.find(params[:id]).localized
    set_discipline_form_state(record: @observation_diary_record)
    authorize @observation_diary_record
  end

  def update
    @observation_diary_record = ObservationDiaryRecord.find(params[:id])
    @observation_diary_record.current_user = current_user
    set_discipline_form_state(record: @observation_diary_record)

    attributes = resource_params.to_unsafe_h
    attributes = attributes.except('discipline_id', :discipline_id) if @general_record

    @observation_diary_record.assign_attributes(attributes)
    @observation_diary_record.discipline_id = nil if @general_record
    @observation_diary_record.requires_discipline = @allow_discipline_edit

    authorize @observation_diary_record

    if @observation_diary_record.save
      respond_with @observation_diary_record, location: observation_diary_records_path
    else
      has_discipline_error = @observation_diary_record.errors[:discipline].present? ||
                            @observation_diary_record.errors[:discipline_id].present?
      set_discipline_form_state(record: @observation_diary_record, force_discipline_edit: has_discipline_error)
      render :edit
    end
  end

  def destroy
    @observation_diary_record = ObservationDiaryRecord.find(params[:id])

    @observation_diary_record.destroy

    respond_with @observation_diary_record, location: observation_diary_records_path
  end

  def history
    @observation_diary_record = ObservationDiaryRecord.find(params[:id]).localized

    authorize @observation_diary_record
  end

  def unities
    @unities ||= begin
      if current_user.teacher?
        Unity.by_teacher(current_teacher.id).ordered
      elsif current_user.has_administrator_access_level?
        Unity.ordered
      else
        Unity.by_user_id(current_user.id).ordered
      end
    end
  end
  helper_method :unities

  def classrooms
    @classrooms ||= Classroom.by_unity(unities.map(&:id))
                             .by_year(current_user_school_year)
                             .ordered
  end
  helper_method :classrooms

  def disciplines
    @disciplines ||= Discipline.where(id: fetch_current_discipline)
  end
  helper_method :disciplines

  private

  def general_record?
    !current_user.teacher?
  end

  def set_discipline_form_state(record: nil, force_discipline_edit: false)
    @general_record = if record&.persisted?
                        record.discipline.blank?
                      else
                        general_record?
                      end
    @allow_discipline_edit = force_discipline_edit || (record&.discipline.blank? && current_user.teacher?)
  end

  def resource_params
    parse_params
    params.require(:observation_diary_record).permit(
      :school_calendar_id,
      :teacher_id,
      :unity_id,
      :classroom_id,
      :discipline_id,
      :date,
      :active_search,
      observation_diary_record_attachments_attributes: [
        :id,
        :attachment,
        :_destroy
      ],
      notes_attributes: [
        :id,
        :description,
        :_destroy,
        student_ids: []
      ]
    )
  end

  def parse_params
    return unless params['observation_diary_record']['notes_attributes'].present?

    params['observation_diary_record']['notes_attributes'].each do |_, v|
      next if v['student_ids'].blank? || v['student_ids'].is_a?(Array)

      v['student_ids'] = v['student_ids'].split(',')
    end
  end

  def fetch_current_discipline
    frequency_type_definer = FrequencyTypeDefiner.new(
      current_user_classroom,
      current_teacher,
      year: current_user_classroom.year
    )
    frequency_type_definer.define!

    current_user_discipline
  end

  def fetch_students_with_observation_diary_records
    Student.joins(observation_diary_record_note_students: :observation_diary_record_note)
           .where(observation_diary_record_notes: { observation_diary_record_id: @observation_diary_records })
           .distinct
           .ordered
  end
end
