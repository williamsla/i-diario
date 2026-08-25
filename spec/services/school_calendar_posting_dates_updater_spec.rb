# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchoolCalendarPostingDatesUpdater, type: :service do
  let(:entity) { Entity.find_by(domain: 'test.host') }
  let(:year) { Date.current.year }
  let(:unity_one) { create(:unity) }
  let(:unity_two) { create(:unity) }

  let!(:semester_calendar_one) do
    create(
      :school_calendar,
      :with_semester_steps,
      unity: unity_one,
      year: year,
      step_type_description: 'Semestre'
    )
  end

  let!(:semester_calendar_two) do
    create(
      :school_calendar,
      :with_semester_steps,
      unity: unity_two,
      year: year,
      step_type_description: 'Semestre'
    )
  end

  subject { described_class.new(year: year) }

  around(:each) do |example|
    entity.using_connection { example.run }
  end

  describe '#groups' do
    let!(:trimester_calendar) do
      create(
        :school_calendar,
        :with_trimester_steps,
        year: year,
        step_type_description: 'Trimestre'
      )
    end

    it 'groups steps by number and type' do
      labels = subject.groups.map(&:label)

      expect(labels).to include('1º Semestre', '2º Semestre', '1º Trimestre', '2º Trimestre', '3º Trimestre')
    end

    it 'orders groups by step type name then number' do
      expect(subject.groups.map(&:label)).to eq([
        '1º Semestre',
        '2º Semestre',
        '1º Trimestre',
        '2º Trimestre',
        '3º Trimestre'
      ])
    end

    it 'counts schools of the same step type together' do
      first_semester = subject.groups.find { |group| group.label == '1º Semestre' }

      expect(first_semester.school_count).to eq(2)
      expect(first_semester.classroom_step_count).to eq(0)
    end
  end

  describe '#apply' do
    let(:new_end_date) { Date.new(year, 8, 15) }

    it 'updates only the filled date for the selected step' do
      first_step_one = semester_calendar_one.steps.find_by!(step_number: 1)
      original_start = first_step_one.start_date_for_posting

      result = subject.apply(
        groups: [
          {
            step_number: 1,
            step_type_description: 'Semestre',
            start_date_for_posting: '',
            end_date_for_posting: I18n.l(new_end_date)
          }
        ]
      )

      expect(result.updated_count).to eq(2)
      expect(result.errors).to be_empty
      expect(first_step_one.reload.end_date_for_posting).to eq(new_end_date)
      expect(first_step_one.start_date_for_posting).to eq(original_start)
      expect(semester_calendar_two.steps.find_by!(step_number: 1).end_date_for_posting).to eq(new_end_date)
      expect(semester_calendar_one.steps.find_by!(step_number: 2).end_date_for_posting).not_to eq(new_end_date)
    end

    it 'does not change calendars of another step type' do
      trimester_calendar = create(
        :school_calendar,
        :with_trimester_steps,
        year: year,
        step_type_description: 'Trimestre'
      )
      original_end = trimester_calendar.steps.find_by!(step_number: 1).end_date_for_posting

      subject.apply(
        groups: [
          {
            step_number: 1,
            step_type_description: 'Semestre',
            end_date_for_posting: I18n.l(new_end_date)
          }
        ]
      )

      expect(trimester_calendar.steps.find_by!(step_number: 1).reload.end_date_for_posting).to eq(original_end)
    end

    it 'updates classroom specific steps when requested' do
      classroom = create(:classroom, unity: unity_one, year: year)
      school_calendar_classroom = create(
        :school_calendar_classroom,
        :school_calendar_classroom_with_semester_steps,
        classroom: classroom,
        school_calendar: semester_calendar_one,
        step_type_description: 'Semestre'
      )

      result = subject.apply(
        groups: [
          {
            step_number: 1,
            step_type_description: 'Semestre',
            end_date_for_posting: I18n.l(new_end_date)
          }
        ],
        apply_to_classroom_steps: true
      )

      classroom_step = school_calendar_classroom.classroom_steps.find_by!(step_number: 1)
      expect(classroom_step.reload.end_date_for_posting).to eq(new_end_date)
      expect(result.updated_count).to eq(3)
    end

    it 'keeps classroom specific steps unchanged when not requested' do
      classroom = create(:classroom, unity: unity_one, year: year)
      school_calendar_classroom = create(
        :school_calendar_classroom,
        :school_calendar_classroom_with_semester_steps,
        classroom: classroom,
        school_calendar: semester_calendar_one,
        step_type_description: 'Semestre'
      )
      classroom_step = school_calendar_classroom.classroom_steps.find_by!(step_number: 1)
      original_end = classroom_step.end_date_for_posting

      subject.apply(
        groups: [
          {
            step_number: 1,
            step_type_description: 'Semestre',
            end_date_for_posting: I18n.l(new_end_date)
          }
        ],
        apply_to_classroom_steps: false
      )

      expect(classroom_step.reload.end_date_for_posting).to eq(original_end)
    end

    it 'registers validation errors without stopping the other schools' do
      invalid_start = Date.new(year, 1, 1) - 1.day

      result = subject.apply(
        groups: [
          {
            step_number: 1,
            step_type_description: 'Semestre',
            start_date_for_posting: I18n.l(invalid_start)
          }
        ]
      )

      expect(result.updated_count).to eq(0)
      expect(result.errors.size).to eq(2)
      expect(result.errors.first[:messages].join).to include('não pode ser menor que a data inicial')
    end

    it 'ignores blank groups' do
      result = subject.apply(
        groups: [
          {
            step_number: 1,
            step_type_description: 'Semestre',
            start_date_for_posting: '',
            end_date_for_posting: ''
          }
        ]
      )

      expect(result).to be_nothing_to_update
    end
  end
end
