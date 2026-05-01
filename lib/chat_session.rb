# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'

class ChatSession
  attr_accessor :name, :model, :messages, :web_search_enabled, :last_response_id
  attr_reader   :file_path

  CHATS_DIR = File.expand_path('../../chats', __FILE__)

  def initialize(model, name: nil, file_path: nil)
    @model              = model
    @messages           = []
    @web_search_enabled = false
    @name               = name || "Chat #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"

    FileUtils.mkdir_p(CHATS_DIR)

    @file_path = if file_path
                   file_path
                 else
                   ts = Time.now.strftime('%Y%m%d_%H%M%S')
                   File.join(CHATS_DIR, "#{ts}.json")
                 end
  end

  # Append a message and immediately persist (crash-safe).
  def add_message(role, content)
    @messages << { role: role.to_s, content: content.to_s }
    save
  end

  def save
    data = {
      name:               @name,
      model_id:           @model[:id],
      model_name:         @model[:name],
      web_search_enabled: @web_search_enabled,
      last_response_id:   @last_response_id,
      messages:           @messages,
      saved_at:           Time.now.iso8601
    }
    File.write(@file_path, JSON.pretty_generate(data))
  rescue StandardError => e
    warn "Warning: could not save chat: #{e.message}"
  end

  def message_count
    @messages.length
  end

  # ── class methods ─────────────────────────────────────────────────────────

  def self.load_from_file(file_path, models)
    raw  = File.read(file_path)
    data = JSON.parse(raw, symbolize_names: true)

    model   = models.find { |m| m[:id] == data[:model_id].to_s } || models.first
    session = new(model, name: data[:name].to_s, file_path: file_path)

    session.messages           = (data[:messages] || []).map do |m|
      { role: m[:role].to_s, content: m[:content].to_s }
    end
    session.web_search_enabled = data[:web_search_enabled] || false
    session.last_response_id   = data[:last_response_id]
    session
  rescue StandardError => e
    warn "Warning: could not load #{file_path}: #{e.message}"
    nil
  end

  def self.list_files
    FileUtils.mkdir_p(CHATS_DIR)
    Dir.glob(File.join(CHATS_DIR, '*.json')).sort.reverse
  end

  def self.latest_file
    list_files.first
  end
end

