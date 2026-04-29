#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.join(__dir__, 'lib')

require 'models_data'
require 'chat_session'
require 'app'

api_key = ENV['OPENAI_ACCESS_TOKEN']

unless api_key && !api_key.strip.empty?
  puts "Error: OPENAI_ACCESS_TOKEN environment variable is not set."
  puts ""
  puts "Set it before running:"
  puts "  export OPENAI_ACCESS_TOKEN=sk-..."
  puts ""
  exit 1
end

begin
  App.new(api_key).run
rescue SystemExit => e
  exit e.status
end

