# encoding: utf-8

require 'curb'
require 'progress_bar'

namespace :sync do
  desc 'Получить список факультетов и групп'
  task :f_and_g => :environment do
    groups = JSON.parse(Curl.get("#{Settings['timetable.url']}/api/v1/groups.json").body_str)

    bar = ProgressBar.new(groups['groups'].count)

    groups['groups'].each do |group|
      faculty = Faculty.find_or_create_by_abbr_and_title(:abbr => group['faculty_abbr'], :title => group['faculty_name'])
      faculty.groups.find_or_create_by_number_and_course(:number => group['number'], :course => group['course'])

      bar.increment!
    end
  end

  desc 'Синхронизация студентов'
  task :students => :environment do
    Group.find_each do |group|
      p "Импорт студентов группы #{group.number}"
      students = JSON.parse(Curl.get("#{Settings['students.url']}/students.json?student_search[group]=#{group.number}").body_str)

      bar = ProgressBar.new(students.count)

      p "Студенты не найдены" if students.empty?

      students.each do |student|
        student = student['student']

        group.students.find_or_initialize_by_contingent_id(student['study_id']).tap do |item|
          item.surname    =  student['lastname']
          item.name       =  student['firstname']
          item.patronymic =  student['patronymic']
          item.save!
        end

        bar.increment!
      end

      (group.students - group.students.where(:contingent_id => students.map{|s| s['student']['study_id']})).each{|student| student.update_attributes(:active => false)}
    end
  end

  desc 'Синхронизация уроков на предстоящий день'
  task :lessons => :environment do
    Group.find_each do |group|
      p "Расписание для #{group} на #{Time.zone.today.strftime('%Y-%m-%d')}"
      LessonSync.new(group.number, Time.zone.today.strftime('%Y-%m-%d'))
    end
  end

  desc 'Синхронизация уроков с START_DATE=%Y-%m-%d'
  task :all_lessons => :environment do
    start_date = Time.zone.parse ENV['START_DATE']
    (start_date.to_date .. Time.zone.today).each do |date|
      Group.find_each do |group|
        p "Расписание для #{group} на #{date.strftime('%Y-%m-%d')}"
        LessonSync.new(group.number, date.strftime('%Y-%m-%d'))
      end
    end
  end
end

class LessonSync
  def initialize(group_number, date)
    get_lessons(group_number, date)
  end

  def get_lessons(group_number, date)
    response = JSON.parse(Curl.get("#{Settings['timetable.url']}/api/v1/timetables/#{group_number}/#{date}").body_str)
    lessons = []

    p '>>>>>>>>> Расписание не найдено' if response['lessons'].empty? || response.has_key?('error')

    bar = ProgressBar.new(response['lessons'].count)

    response['lessons'].each do |lesson|
      discipline = Discipline.find_or_create_by_abbr_and_title(lesson['discipline'])
      lesson_obj = discipline.lessons.find_or_initialize_by_timetable_id(lesson['timetable_id']).tap do |item|
        item.classroom    = lesson['classroom']
        item.date_on      = Time.zone.parse(date)
        item.kind         = lesson['kind']
        item.order_number = lesson['order_number']
        item.note         = lesson['note']
        item.group_id     = Group.find_by_number(group_number).id
        item.save!
      end

      lesson['lecturers'].each do |lecturer|
        lecturer_obj = Lecturer.find_or_create_by_surname_and_name_and_patronymic(
          :surname => lecturer['lastname'],
          :name => lecturer['firstname'],
          :patronymic => lecturer['middlename']
        )

        Realize.find_or_create_by_lecturer_id_and_lesson_id(:lecturer_id => lecturer_obj.id, :lesson_id => lesson_obj.id)
      end

      lessons << lesson_obj
    end
    lessons
  end
end
