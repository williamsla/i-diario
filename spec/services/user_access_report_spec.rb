# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserAccessReport, type: :service do
  let(:teacher_role) { create(:role, :teacher, name: 'Professor') }
  let(:student_role) { create(:role, name: 'Estudante', access_level: AccessLevel::STUDENT) }
  let(:school_a) { create(:unity, name: 'Escola A') }
  let(:school_b) { create(:unity, name: 'Escola B') }

  def sign_in_record(user, ip = '127.0.0.1')
    UserLogin.create!(user: user, sign_in_ip: ip)
  end

  it 'counts distinct users of the selected role by school and once in the total' do
    teacher = create(:user)
    create(:user_role, user: teacher, role: teacher_role, unity: school_a)
    create(:user_role, user: teacher, role: teacher_role, unity: school_b)
    sign_in_record(teacher)
    sign_in_record(teacher, '10.0.0.2')

    other_teacher = create(:user)
    create(:user_role, user: other_teacher, role: teacher_role, unity: school_a)
    sign_in_record(other_teacher, '10.0.0.3')

    without_login = create(:user)
    create(:user_role, user: without_login, role: teacher_role, unity: school_a)

    other_role_user = create(:user)
    create(:user_role, user: other_role_user, role: student_role, unity: nil)
    sign_in_record(other_role_user, '10.0.0.4')

    report = described_class.new(teacher_role.id)

    expect(report.rows.map { |row| [row.name, row.count] }).to eq([['Escola A', 2], ['Escola B', 1]])
    expect(report.total).to eq(2)
  end

  it 'puts users without a school in Sem escola' do
    student = create(:user)
    create(:user_role, user: student, role: student_role, unity: nil)
    sign_in_record(student)

    report = described_class.new(student_role.id)

    expect(report.rows.map { |row| [row.name, row.count] }).to eq([['Sem escola', 1]])
    expect(report.total).to eq(1)
  end

  it 'returns nothing when no role is selected' do
    report = described_class.new(nil)

    expect(report.role).to be_nil
    expect(report.rows).to eq([])
    expect(report.total).to eq(0)
  end

  it 'limits schools and roles when the viewer is an employee' do
    employee_role = create(:role, :employee, name: 'Servidor')
    report = described_class.new(
      teacher_role.id,
      allowed_role_ids: [employee_role.id, student_role.id],
      school_id: school_a.id
    )

    expect(report.role).to be_nil
    expect(report.rows).to eq([])

    teacher = create(:user)
    create(:user_role, user: teacher, role: employee_role, unity: school_a)
    create(:user_role, user: teacher, role: employee_role, unity: school_b)
    sign_in_record(teacher)

    scoped = described_class.new(
      employee_role.id,
      allowed_role_ids: [employee_role.id, student_role.id],
      school_id: school_a.id
    )

    expect(scoped.rows.map { |row| [row.name, row.count] }).to eq([['Escola A', 1]])
    expect(scoped.total).to eq(1)
  end

  it 'counts logins of the selected school by month' do
    teacher = create(:user)
    create(:user_role, user: teacher, role: teacher_role, unity: school_a)
    march = UserLogin.create!(user: teacher, sign_in_ip: '10.0.0.1')
    april = UserLogin.create!(user: teacher, sign_in_ip: '10.0.0.2')
    march.update_column(:created_at, Time.zone.local(2026, 3, 10, 8))
    april.update_column(:created_at, Time.zone.local(2026, 4, 2, 8))
    UserLogin.create!(user: teacher, sign_in_ip: '10.0.0.3').update_column(
      :created_at,
      Time.zone.local(2026, 3, 20, 8)
    )

    report = described_class.new(teacher_role.id, chart_unity_id: school_a.id, year: 2026)
    counts = report.monthly_accesses

    expect(report.chart_school_name).to eq('Escola A')
    expect(counts.size).to eq(12)
    expect(counts.map { |month| [month.label, month.count] }).to include(['Mar/2026', 2], ['Abr/2026', 1])
  end

  it 'compares the same months of the previous year' do
    teacher = create(:user)
    create(:user_role, user: teacher, role: teacher_role, unity: school_a)
    UserLogin.create!(user: teacher, sign_in_ip: '10.0.0.1').update_column(
      :created_at,
      Time.zone.local(2026, 3, 10, 8)
    )
    UserLogin.create!(user: teacher, sign_in_ip: '10.0.0.2').update_column(
      :created_at,
      Time.zone.local(2025, 3, 4, 8)
    )
    UserLogin.create!(user: teacher, sign_in_ip: '10.0.0.3').update_column(
      :created_at,
      Time.zone.local(2025, 3, 18, 8)
    )

    report = described_class.new(teacher_role.id, chart_unity_id: school_a.id, year: 2026)
    previous = report.previous_monthly_accesses

    expect(report.month_labels).to eq(%w[Jan Fev Mar Abr Mai Jun Jul Ago Set Out Nov Dez])
    expect(previous.size).to eq(12)
    expect(previous.map { |month| [month.label, month.count] }).to include(['Mar/2025', 2], ['Abr/2025', 0])
    expect(report.rows.map { |row| [row.name, row.count] }).to eq([['Escola A', 1]])
  end

  it 'counts each login once when the chart includes every school' do
    teacher = create(:user)
    create(:user_role, user: teacher, role: teacher_role, unity: school_a)
    create(:user_role, user: teacher, role: teacher_role, unity: school_b)
    UserLogin.create!(user: teacher, sign_in_ip: '10.0.0.1').update_column(
      :created_at,
      Time.zone.local(2026, 3, 10, 8)
    )

    other = create(:user)
    create(:user_role, user: other, role: teacher_role, unity: school_b)
    UserLogin.create!(user: other, sign_in_ip: '10.0.0.2').update_column(
      :created_at,
      Time.zone.local(2026, 3, 12, 8)
    )

    report = described_class.new(teacher_role.id, chart_unity_id: 'all', year: 2026)
    march = report.monthly_accesses.find { |month| month.label == 'Mar/2026' }

    expect(report.chart_school_name).to eq('Geral')
    expect(report.chart_for_all?).to eq(true)
    expect(march.count).to eq(2)

    scoped = described_class.new(
      teacher_role.id,
      chart_unity_id: 'all',
      school_id: school_a.id,
      year: 2026
    )

    expect(scoped.monthly_accesses.find { |month| month.label == 'Mar/2026' }.count).to eq(1)
  end

  it 'uses the enrollment of the selected year as the student school' do
    student_user = create(:user, student: create(:student))
    create(:user_role, user: student_user, role: student_role, unity: nil)
    enroll_student(student_user, school_a, 2026)
    enroll_student(student_user, school_b, 2026)
    sign_in_record(student_user).update_column(:created_at, Time.zone.local(2026, 5, 2, 8))

    previous_year = create(:user, student: create(:student))
    create(:user_role, user: previous_year, role: student_role, unity: nil)
    enroll_student(previous_year, school_a, 2025)
    sign_in_record(previous_year).update_column(:created_at, Time.zone.local(2026, 5, 3, 8))

    report = described_class.new(student_role.id, year: 2026)

    expect(report.rows.map { |row| [row.name, row.count] }).to eq(
      [['Escola A', 1], ['Escola B', 1], ['Sem escola', 1]]
    )
    expect(report.total).to eq(2)

    chart = described_class.new(student_role.id, chart_unity_id: school_a.id, year: 2026)
    may = chart.monthly_accesses.find { |month| month.label == 'Mai/2026' }

    expect(may.count).to eq(1)

    scoped = described_class.new(
      student_role.id,
      allowed_role_ids: [student_role.id],
      school_id: school_a.id,
      year: 2026
    )

    expect(scoped.rows.map { |row| [row.name, row.count] }).to eq([['Escola A', 1]])
    expect(scoped.total).to eq(1)
  end

  def enroll_student(user, unity, year)
    classroom = create(:classroom, unity: unity, year: year)
    classrooms_grade = create(:classrooms_grade, classroom: classroom)
    enrollment = create(:student_enrollment, student: user.student)
    create(
      :student_enrollment_classroom,
      student_enrollment: enrollment,
      classrooms_grade: classrooms_grade
    )
  end

  it 'ignores logins from another school year' do
    teacher = create(:user)
    create(:user_role, user: teacher, role: teacher_role, unity: school_a)
    sign_in_record(teacher).update_column(:created_at, Time.zone.local(2025, 11, 2, 8))

    report = described_class.new(teacher_role.id, year: 2026)

    expect(report.rows).to eq([])
    expect(report.total).to eq(0)
  end
end
