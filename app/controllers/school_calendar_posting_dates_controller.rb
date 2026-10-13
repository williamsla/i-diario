# frozen_string_literal: true

class SchoolCalendarPostingDatesController < ApplicationController
  def edit
    authorize SchoolCalendarPostingDates

    load_form
  end

  def update
    authorize SchoolCalendarPostingDates

    @result = updater.apply(
      groups: group_params,
      apply_to_classroom_steps: apply_to_classroom_steps?
    )
    @apply_to_classroom_steps = apply_to_classroom_steps?

    if @result.nothing_to_update?
      flash.now[:alert] = t('.nothing_to_update')
    elsif @result.errors.empty?
      flash.now[:notice] = t('.notice', count: @result.updated_count)
    else
      flash.now[:alert] = t('.alert', updated: @result.updated_count, errors: @result.errors.size)
    end

    load_form
    render :edit
  end

  private

  def updater
    SchoolCalendarPostingDatesUpdater.new(year: current_school_year)
  end

  def load_form
    @year = current_school_year
    @groups = updater.groups
    @apply_to_classroom_steps = true if @apply_to_classroom_steps.nil?
  end

  def apply_to_classroom_steps?
    ActiveRecord::Type::Boolean.new.cast(params[:apply_to_classroom_steps])
  end

  GROUP_PARAM_KEYS = %w[
    step_number
    step_type_description
    start_date_for_posting
    end_date_for_posting
  ].freeze

  def group_params
    raw = params[:groups]
    return [] if raw.blank?

    list = if raw.respond_to?(:to_unsafe_h)
             raw.to_unsafe_h.values
           elsif raw.respond_to?(:values)
             raw.values
           else
             Array(raw)
           end

    list.map do |group|
      hash = group.respond_to?(:to_unsafe_h) ? group.to_unsafe_h : group.to_h
      hash.with_indifferent_access.slice(*GROUP_PARAM_KEYS)
    end
  end
end
