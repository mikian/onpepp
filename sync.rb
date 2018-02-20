#!/usr/bin/env ruby

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
    response = self.class.get('/users.json', format: :plain)
    JSON.parse response, symbolize_names: true
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
