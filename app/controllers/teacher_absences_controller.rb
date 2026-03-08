# frozen_string_literal: true

class TeacherAbsencesController < ApplicationController
  before_action :require_current_teacher, only: [:new, :create]
  before_action :require_current_classroom, only: [:new, :create]
  before_action :set_teacher_absence, only: [:show, :edit, :update, :destroy, :history]
  before_action :require_allow_to_modify_prev_years, only: [:create, :update, :destroy]

  has_scope :page, default: 1
  has_scope :per, default: 10

  def index
    set_options_by_user
    @teacher_absences = fetch_teacher_absences
    authorize @teacher_absences
  end

  def new
    @teacher_absence = TeacherAbsence.new
    @teacher_absence.unity = current_unity
    @teacher_absence.school_calendar = current_school_calendar
    @teacher_absence.teacher = current_teacher
    @teacher_absence.user = current_user
    @teacher_absence.coverage = TeacherAbsenceCoverage::BY_CLASSROOM
    @teacher_absence.classroom = current_user_classroom
    @teacher_absence.discipline = current_user_discipline if current_user_discipline.present?
    @teacher_absence.absence_date = params[:frequency_date].present? ? params[:frequency_date] : Date.current
    @teacher_absence.periods = params[:periods].presence || params[:period].presence
    @teacher_absence.class_number = params[:class_number].presence&.to_i
    set_options_by_user
    set_disciplines
    authorize @teacher_absence
  end

  def create
    @teacher_absence = TeacherAbsence.new(resource_params)
    @teacher_absence.unity = current_unity
    @teacher_absence.school_calendar = current_school_calendar
    @teacher_absence.teacher = current_teacher
    @teacher_absence.user = current_user

    authorize @teacher_absence

    if @teacher_absence.save
      flash[:notice] = I18n.t('flash.teacher_absences.create.notice')
      respond_with @teacher_absence, location: teacher_absences_path
    else
      set_options_by_user
      set_disciplines
      render :new
    end
  end

  def show
    authorize @teacher_absence
  end

  def edit
    set_options_by_user
    set_disciplines(@teacher_absence.teacher_id)
    # Garante que a turma do registro apareça nas opções (ex.: admin editando)
    if @classrooms.present? && @teacher_absence.classroom_id.present?
      @classrooms = (@classrooms + [@teacher_absence.classroom]).uniq
    elsif @teacher_absence.classroom_id.present?
      @classrooms = [@teacher_absence.classroom]
    end
    authorize @teacher_absence
  end

  def update
    authorize @teacher_absence

    if @teacher_absence.update(resource_params)
      flash[:notice] = I18n.t('flash.teacher_absences.update.notice')
      respond_with @teacher_absence, location: teacher_absences_path
    else
      set_options_by_user
      set_disciplines(@teacher_absence.teacher_id)
      render :edit
    end
  end

  def destroy
    authorize @teacher_absence
    @teacher_absence.destroy
    flash[:notice] = I18n.t('flash.teacher_absences.destroy.notice')
    respond_with @teacher_absence, location: teacher_absences_path
  end

  def history
    authorize @teacher_absence
    respond_with @teacher_absence
  end

  private

  def resource_params
    permitted = params.require(:teacher_absence).permit(
      :coverage,
      :classroom_id,
      :discipline_id,
      :absence_date,
      :reason,
      :will_make_up,
      :make_up_date,
      :class_number,
      periods: [],
      teacher_absence_attachments_attributes: [
        :id,
        :attachment,
        :_destroy
      ]
    )
    # Quando abrangência não é "turma específica", não vincular turma
    if permitted[:coverage].present? && permitted[:coverage] != TeacherAbsenceCoverage::BY_CLASSROOM
      permitted[:classroom_id] = nil
    end
    permitted
  end

  def set_options_by_user
    if current_user.current_role_is_admin_or_employee?
      @classrooms ||= [current_user_classroom].compact
    else
      fetch_linked_by_teacher
    end
    @classrooms ||= []
  end

  def fetch_linked_by_teacher
    return unless current_teacher.present?

    @fetch_linked_by_teacher ||= TeacherClassroomAndDisciplineFetcher.fetch!(
      current_teacher.id,
      current_unity,
      current_school_year
    )
    @classrooms ||= @fetch_linked_by_teacher[:classrooms] || []
  end

  def set_disciplines(teacher_id = nil)
    tid = teacher_id || current_teacher&.id
    return unless tid.present?

    @disciplines = Discipline
                   .by_teacher_id(tid)
                   .not_descriptor
                   .not_grouper
                   .ordered
    @disciplines = @disciplines.by_classroom_id(@teacher_absence.classroom_id) if @teacher_absence.classroom_id.present?
  end

  def set_teacher_absence
    @teacher_absence = TeacherAbsence.find(params[:id])
  end

  def fetch_teacher_absences
    scope = TeacherAbsence
             .includes(:classroom, :discipline)
             .by_unity(current_unity)
             .ordered

    if current_user_classroom.present?
      scope = scope.where(
        '(teacher_absences.classroom_id = ? OR teacher_absences.classroom_id IS NULL)',
        current_user_classroom.id
      )
    end
    scope = scope.by_teacher(current_teacher.id) if current_teacher.present? && !current_user.current_role_is_admin_or_employee?

    apply_scopes(scope)
  end
end
