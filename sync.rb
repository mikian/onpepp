#!/usr/bin/env ruby

# Simple script to sync drivers and schedules between EasyPepp and Onfleet
#
# Usage:
#
#  ONFLEET_APIKEY=<your_key_here> EASYPEPP_ACCOUNT=<subdomain> EASYPEPP_USERNAME=<email> EASYPEPP_PASSWORD=<password> ./sync.rb
#

require 'bundler/inline'
require 'logger'

gemfile do
  source 'https://rubygems.org'

  gem 'httparty'
  gem 'onfleet-ruby'
  gem 'pry'
end

class EasyPepp
  include HTTParty
  logger ::Logger.new(STDOUT), :debug, :apache

  base_uri "https://api.staffomaticapp.com/v3/#{ENV.fetch('EASYPEPP_ACCOUNT')}"
  basic_auth ENV.fetch('EASYPEPP_USERNAME'), ENV.fetch('EASYPEPP_PASSWORD')

  def locations
    response = self.class.get('/locations.json', format: :plain)
    JSON.parse response, symbolize_names: true
  end

  def users
    @users ||= begin
      response = self.class.get('/users.json', format: :plain)
      JSON.parse response, symbolize_names: true
    end
  end

  def shifts
    @shifts ||= begin
      response = self.class.get('/shifts.json', format: :plain)
      JSON.parse response, symbolize_names: true
    end
  end
end

class OnFleet
  include HTTParty
  logger ::Logger.new(STDOUT), :debug, :curl

  base_uri 'https://onfleet.com/api/v2'
  basic_auth ENV.fetch('ONFLEET_APIKEY'), ''
  headers 'Content-Type' => 'application/json', 'Accept' => 'application/json'

  def update_schedule(worker_id, schedule)
    self.class.put(
      "/workers/#{worker_id}/schedule",
      body: schedule.to_json,
      # format: :json,
      headers: { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
    )
  end
end

Onfleet.api_key = ENV.fetch('ONFLEET_APIKEY')

# Sync drivers
easypepp = EasyPepp.new
easypepp.users.each do |user|
  params = {
    name: "#{user[:first_name]} #{user[:last_name]}",
    phone: [user[:phone_number_mobile], user[:phone_number_office], "07903 123 123"].compact.reject(&:empty?).first,
    email: user[:email],
    teams: [Onfleet::Team.list.first.id],
    vehicle: { type: 'CAR' }
  }

  worker = Onfleet::Worker.list.find { |w| w.name == "#{user[:first_name]} #{user[:last_name]}" }
  if worker
    Onfleet::Worker.update(worker.id, params)
  else
    Onfleet::Worker.create(params)
  end
end

# Sync schedules
schedule = easypepp.shifts.each_with_object(Hash.new {|h, k| h[k] = []}) do |shift, schedule|
  shift[:assigned_user_ids].each do |uid|
    driver = easypepp.users.find { |u| u[:id] == uid }
    worker = Onfleet::Worker.list.find { |w| w.name == "#{driver[:first_name]} #{driver[:last_name]}" }

    starts_at = Time.parse(shift[:starts_at])
    ends_at = Time.parse(shift[:ends_at])

    schedule[worker.id] << {
      date: starts_at.strftime('%Y-%m-%d'),
      shifts: [[starts_at.strftime('%s').to_i * 1000, ends_at.strftime('%s').to_i * 1000]],
      timezone: 'Europe/London'
    }
  end

  schedule
end
schedule.each do |worker, entries|
  OnFleet.new.update_schedule(worker, entries: entries)
end
