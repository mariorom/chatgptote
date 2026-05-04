# frozen_string_literal: true

require 'openai'
require 'tty-prompt'
require 'tty-spinner'
require 'tty-markdown'
require 'pastel'
require 'io/console'
require 'json'

# Make Escape cancel any tty-prompt select/ask menu.
TTY::Prompt::List.prepend(Module.new do
  def keyescape(*) = raise TTY::Reader::InputInterrupt
end)

class App
  COMMANDS = %w[
    select_model help exit
    enable_websearch disable_websearch
    clear new name chats delete
  ].freeze

  COMMAND_DESC = {
    'select_model'      => 'Switch to a different model',
    'help'              => 'Show available commands',
    'exit'              => 'Exit the app',
    'enable_websearch'  => 'Enable web search (model must support it)',
    'disable_websearch' => 'Disable web search',
    'clear'             => 'Clear the console',
    'new'               => 'Start a new chat session',
    'name'              => 'Rename the current session',
    'chats'             => 'Browse & load a previous session',
    'delete'            => 'Delete the current chat session'
  }.freeze

  def initialize(api_key)
    @client        = OpenAI::Client.new(access_token: api_key)
    @pastel        = Pastel.new
    @prompt        = TTY::Prompt.new(interrupt: :signal)
    @session       = nil
    @model         = nil
    @input_history = []
    @history_pos   = nil
    @history_draft = nil
  end

  def run
    print_banner
    select_model
    init_session

    trap('INT') do
      puts "\n#{@pastel.yellow('Saving and exiting...')}"
      save_session
      exit 0
    end

    main_loop
  end

  private

  # ── Banner ────────────────────────────────────────────────────────────────

  def print_banner
    puts @pastel.cyan.bold(<<~BANNER)
      ╔══════════════════════════════════╗
      ║        ChatGPTote  v1.0          ║
      ║  Your terminal ChatGPT client    ║
      ╚══════════════════════════════════╝
    BANNER
    puts @pastel.dim("Type a message and press Enter.  Ctrl+J for newline.  Start with / for commands.\n")
  end

  # ── Model selection ───────────────────────────────────────────────────────

  def select_model
    name_w = MODELS.map { |m| m[:name].length }.max
    in_w   = MODELS.map { |m| m[:input_price].length }.max
    out_w  = MODELS.map { |m| m[:output_price].length }.max
    api_w  = 'responses'.length   # width of the longer tag

    choices = MODELS.map do |m|
      ws     = m[:web_search_capable] ? @pastel.green('🔍') : '  '
      api_tag = if m[:responses_api]
                  @pastel.cyan('responses'.ljust(api_w))
                else
                  @pastel.dim('chat     '.ljust(api_w))
                end
      label = "#{m[:name].ljust(name_w)}  #{ws}  #{api_tag}  " \
              "#{m[:input_price].ljust(in_w)}  " \
              "#{m[:output_price].ljust(out_w)}  " \
              "#{@pastel.dim(m[:description])}"
      { name: label, value: m }
    end

    @model = @prompt.select(
      "#{@pastel.bold('Select a model')} (↑↓ to navigate, Enter to confirm):",
      choices,
      per_page: MODELS.length,
      cycle: true
    )
  rescue TTY::Reader::InputInterrupt, Interrupt
    puts "\nGoodbye!"
    exit 0
  end

  # ── Session bootstrap ─────────────────────────────────────────────────────

  def init_session
    latest = ChatSession.latest_file

    if latest
      session = ChatSession.load_from_file(latest, MODELS)
      if session
        @session = session
        @model   = session.model   # restore the model from last session
        @input_history = session.messages
                           .select { |m| m[:role] == 'user' }
                           .map    { |m| m[:content] }
        puts @pastel.dim("\nRestored session: #{@pastel.bold(session.name)}")
        puts @pastel.dim("  Model: #{session.model[:name]}  ·  #{session.message_count} message(s)")
        show_recent_messages(session) if session.message_count > 0
        puts
        return
      end
    end

    @session = ChatSession.new(@model)
    puts @pastel.dim("\nNew session started: #{@pastel.bold(@session.name)}\n\n")
  end

  def show_recent_messages(session, count: 6)
    msgs = session.messages.last(count)
    puts @pastel.dim("\n  ── last #{msgs.length} message(s) ──")
    msgs.each do |msg|
      case msg[:role]
      when 'user'
        puts "  #{@pastel.cyan.bold('You:')} #{msg[:content]}"
      when 'assistant'
        body = msg[:content].to_s
        body = "#{body[0, 280]}#{@pastel.dim('…')}" if body.length > 280
        puts "  #{@pastel.green.bold('Assistant:')} #{body}"
      end
    end
    puts @pastel.dim("  ── end of history ──")
  end

  # ── Main loop ─────────────────────────────────────────────────────────────

  # Only persist a session that actually has messages.
  def save_session
    @session.save if @session&.message_count.to_i > 0
  end

  def main_loop
    loop do
      input = read_input(build_prompt_str)
      next if input.nil? || input.strip.empty?

      if input.start_with?('/')
        handle_command(input[1..].strip)
      else
        send_message(input.strip)
      end
    rescue Interrupt
      puts "\n#{@pastel.yellow('Saving and exiting...')}"
      save_session
      exit 0
    rescue EOFError
      save_session
      exit 0
    rescue StandardError => e
      puts @pastel.red("Error: #{e.message}")
    end
  end


  def build_prompt_str
    ws_tag = if @model[:web_search_capable]
               @session&.web_search_enabled ? @pastel.green(' 🔍on') : @pastel.dim(' 🔍off')
             else
               ''
             end
    "#{@pastel.cyan.bold(@model[:short_name])}#{ws_tag} #{@pastel.bold('❯')} "
  end

  # ── Input: raw loop with cursor movement, history, multi-line ────────────

  def read_input(prompt_str)
    @history_pos   = nil
    @history_draft = nil
    @prev_input_rows = nil   # reset wrap-row counter for each fresh prompt
    buf = +''   # mutable string (file has frozen_string_literal: true)
    cur = 0   # cursor position within buf

    redraw_input(prompt_str, buf, cur)

    loop do
      ch = read_raw_char
      return nil if ch.nil?
      if ch == "\u0003"   # Ctrl+C — cancel current input, return to fresh prompt
        puts
        return nil
      end
      raise EOFError if ch == "\u0004"

      case ch
      # ── Submit (Enter = \r) ───────────────────────────────────────────────
      when "\r"
        puts
        return buf

      # ── Insert newline (Ctrl+J = \n) ──────────────────────────────────────
      when "\n"
        buf.insert(cur, "\n")
        cur += 1
        redraw_input(prompt_str, buf, cur)

      # ── Command picker (only when buf is empty) ───────────────────────────
      when '/'
        if buf.empty?
          puts
          cmd = pick_command
          puts
          return cmd ? "/#{cmd}" : nil
        else
          buf.insert(cur, '/')
          cur += 1
          redraw_input(prompt_str, buf, cur)
        end

      # ── Backspace ─────────────────────────────────────────────────────────
      when "\x7f", "\b"
        if cur > 0
          buf = +(buf[0...cur - 1] + buf[cur..])
          cur -= 1
          redraw_input(prompt_str, buf, cur)
        end

      # ── Escape sequences (arrows, Home, End, Alt+Enter) ───────────────────
      when "\e"
        seq = read_escape_seq
        case seq
        when '[A'                  # ↑ history back
          if (entry = history_back(buf))
            buf = +entry
            cur = buf.length
            redraw_input(prompt_str, buf, cur)
          end
        when '[B'                  # ↓ history forward
          entry = history_forward
          if entry
            buf = +entry
            cur = buf.length
            redraw_input(prompt_str, buf, cur)
          end
        when '[C'                  # → right
          if cur < buf.length
            cur += 1
            redraw_input(prompt_str, buf, cur)
          end
        when '[D'                  # ← left
          if cur > 0
            cur -= 1
            redraw_input(prompt_str, buf, cur)
          end
        when '[H', 'OH', '[1~'     # Home
          cur = 0
          redraw_input(prompt_str, buf, cur)
        when '[F', 'OF', '[4~'     # End
          cur = buf.length
          redraw_input(prompt_str, buf, cur)
        when '[3~'                 # Delete key (forward delete)
          if cur < buf.length
            buf = +(buf[0...cur] + buf[cur + 1..])
            redraw_input(prompt_str, buf, cur)
          end
        when "\r", "\n"            # Alt+Enter → insert newline
          buf.insert(cur, "\n")
          cur += 1
          redraw_input(prompt_str, buf, cur)
        end

      # ── Printable characters ──────────────────────────────────────────────
      when /\A[\x20-\x7e\t]\z/
        @history_pos = nil
        buf.insert(cur, ch)
        cur += 1
        redraw_input(prompt_str, buf, cur)
      end
    end
  end

  # Redraw the entire input area, then reposition the terminal cursor to `cur`.
  # Multi-line buffers show a "↵ " continuation prefix on each extra line.
  # Correctly handles text that wraps beyond the terminal width.
  def redraw_input(prompt_str, buf, cur)
    term_w = (IO.console&.winsize&.last || 80).clamp(8, 999)

    visible_prompt = prompt_str.gsub(/\e\[[0-9;]*[mGKJABCDHF]/, '')
    prompt_w = Unicode::DisplayWidth.of(visible_prompt)

    logical_lines = buf.split("\n", -1)
    logical_lines = [''] if logical_lines.empty?

    # Helper: how many terminal rows does one logical line occupy?
    line_rows = lambda do |text, prefix_w|
      total = prefix_w + Unicode::DisplayWidth.of(text)
      total.zero? ? 1 : ((total - 1) / term_w) + 1
    end

    # Total terminal rows the rendered input occupies
    total_term_rows = logical_lines.each_with_index.sum do |line, i|
      line_rows.call(line, i == 0 ? prompt_w : 4)
    end

    # ── Move back to the very first row of the previous render ───────────────
    rows_up = (@prev_input_rows || 1) - 1
    print "\e[#{rows_up}A" if rows_up > 0
    print "\r\e[J"

    # ── Render prompt + logical lines ────────────────────────────────────────
    print prompt_str
    logical_lines.each_with_index do |line, i|
      print "\n  ↵ " if i > 0
      print line
    end

    @prev_input_rows = total_term_rows

    # ── Reposition the terminal cursor to `cur` ───────────────────────────────
    # Determine which logical line and column-within-that-line `cur` falls on.
    cur_logical_lines = buf[0...cur].split("\n", -1)
    cur_logical_lines = [''] if cur_logical_lines.empty?
    cur_logical_idx   = cur_logical_lines.length - 1
    cur_col_in_logical = Unicode::DisplayWidth.of(cur_logical_lines.last)

    # Sum terminal rows for all logical lines before the cursor's logical line.
    term_row_of_cursor = logical_lines.first(cur_logical_idx).each_with_index.sum do |line, i|
      line_rows.call(line, i == 0 ? prompt_w : 4)
    end

    # Within the cursor's logical line, add the wrapped rows before the cursor column.
    prefix_w_cur   = cur_logical_idx == 0 ? prompt_w : 4
    abs_col_cursor = prefix_w_cur + cur_col_in_logical
    term_row_of_cursor += abs_col_cursor / term_w
    term_col_of_cursor  = abs_col_cursor % term_w

    # We are currently at the last terminal row of the render; move up to cursor row.
    rows_below_cursor = (total_term_rows - 1) - term_row_of_cursor
    print "\e[#{rows_below_cursor}A" if rows_below_cursor > 0
    print "\r"
    print "\e[#{term_col_of_cursor}C" if term_col_of_cursor > 0

    $stdout.flush
  end

  # Read exactly one char in raw mode (no echo).
  def read_raw_char
    $stdin.raw(&:getc)
  rescue
    nil
  end

  # Read and return the bytes of an ANSI/VT escape sequence after \e.
  # A bare \e followed quickly by \r/\n is treated as Alt+Enter (returns "\r").
  def read_escape_seq
    seq = +''
    ready = IO.select([$stdin], nil, nil, 0.08)
    return seq unless ready   # bare Escape

    ch = $stdin.raw { $stdin.getc }
    seq += ch.to_s

    case ch
    when '['
      loop do
        ready2 = IO.select([$stdin], nil, nil, 0.05)
        break unless ready2
        c = $stdin.raw { $stdin.getc }
        seq += c.to_s
        break if c =~ /[A-Za-z~]/
      end
    when 'O'
      ready2 = IO.select([$stdin], nil, nil, 0.05)
      seq += $stdin.raw { $stdin.getc }.to_s if ready2
    when "\r", "\n"
      seq = ch   # Alt+Enter
    end

    seq
  rescue
    seq
  end

  # Move one step back in history; saves the current draft on first press.
  def history_back(current_buf = nil)
    return nil if @input_history.empty?

    if @history_pos.nil?
      @history_draft = current_buf
      @history_pos   = @input_history.length - 1
    elsif @history_pos > 0
      @history_pos -= 1
    else
      return nil
    end
    @input_history[@history_pos]
  end

  # Move one step forward; restores the saved draft when past the newest entry.
  def history_forward
    return nil if @history_pos.nil?

    if @history_pos < @input_history.length - 1
      @history_pos += 1
      @input_history[@history_pos]
    else
      @history_pos = nil
      @history_draft || +''
    end
  end

  # ── Slash-command picker (tty-prompt with live filtering) ─────────────────

  def pick_command
    choices = COMMANDS.map do |c|
      { name: "#{c.ljust(22)} #{@pastel.dim(COMMAND_DESC[c])}", value: c }
    end
    choices << { name: @pastel.dim('← cancel'), value: nil }

    @prompt.select(
      'Command:',
      choices,
      filter:   true,
      per_page: choices.length,
      cycle:    false
    )
  rescue TTY::Reader::InputInterrupt, Interrupt
    nil
  end

  # ── Command handlers ──────────────────────────────────────────────────────

  def handle_command(cmd)
    case cmd
    when 'select_model'     then cmd_select_model
    when 'help'             then cmd_help
    when 'exit'             then cmd_exit
    when 'enable_websearch' then cmd_websearch(true)
    when 'disable_websearch'then cmd_websearch(false)
    when 'clear'            then cmd_clear
    when 'new'              then cmd_new
    when 'name'             then cmd_name
    when 'chats'            then cmd_chats
    when 'delete'           then cmd_delete
    else
      puts @pastel.red("Unknown command: /#{cmd}   (type /help for help)")
    end
  end

  def cmd_select_model
    select_model
    @session.model = @model
    save_session
    puts @pastel.green("✓ Switched to #{@model[:name]}")
  end

  def cmd_help
    puts "\n#{@pastel.bold('Available Commands')}"
    puts '─' * 52
    COMMANDS.each do |c|
      puts "  #{@pastel.cyan("/#{c.ljust(22)}")}  #{COMMAND_DESC[c]}"
    end
    puts '─' * 52
    puts
  end

  def cmd_exit
    puts @pastel.yellow('Saving and exiting…')
    save_session
    exit 0
  end

  def cmd_websearch(enable)
    unless @model[:web_search_capable]
      puts @pastel.yellow("#{@model[:name]} does not support web search.")
      return
    end

    @session.web_search_enabled = enable
    save_session

    if enable
      puts @pastel.green("✓ Web search enabled for #{@model[:name]}")
    else
      puts @pastel.yellow("✓ Web search disabled for #{@model[:name]}")
    end
  end

  def cmd_clear
    system('clear') || system('cls')
  end

  def cmd_new
    prev_ws = @session&.web_search_enabled
    save_session
    @session = ChatSession.new(@model)
    @session.web_search_enabled = prev_ws if prev_ws
    puts @pastel.green("✓ New chat session: #{@session.name}")
  end

  def cmd_name
    new_name = @prompt.ask('Session name:', value: @session.name)
    return if new_name.nil? || new_name.strip.empty?

    @session.name = new_name.strip
    save_session
    puts @pastel.green("✓ Renamed to: #{@session.name}")
  rescue TTY::Reader::InputInterrupt, Interrupt
    puts "\nCanceled."
  end

  def cmd_chats
    files = ChatSession.list_files

    if files.empty?
      puts @pastel.yellow('No saved chat sessions found.')
      return
    end

    choices = files.map do |f|
      begin
        data      = JSON.parse(File.read(f), symbolize_names: true)
        name      = data[:name]     || File.basename(f, '.json')
        mname     = data[:model_name] || data[:model_id] || '?'
        count     = (data[:messages] || []).length
        saved     = data[:saved_at] ? Time.parse(data[:saved_at]).strftime('%Y-%m-%d %H:%M') : '?'
        label     = "#{name}  #{@pastel.dim("│ #{mname} · #{count} msg · #{saved}")}"
        { name: label, value: f }
      rescue
        { name: File.basename(f), value: f }
      end
    end
    choices << { name: @pastel.dim('(Cancel)'), value: nil }

    selected = @prompt.select(
      'Select session:',
      choices,
      per_page: [choices.length, 16].min,
      cycle:    false
    )

    return unless selected

    loaded = ChatSession.load_from_file(selected, MODELS)
    if loaded
      @session = loaded
      @model   = loaded.model
      puts @pastel.green("✓ Loaded: #{loaded.name}")
      puts @pastel.dim("  Model: #{loaded.model[:name]} · #{loaded.message_count} message(s)")
      show_recent_messages(loaded) if loaded.message_count > 0
      puts
    else
      puts @pastel.red('Failed to load session.')
    end
  rescue TTY::Reader::InputInterrupt, Interrupt
    puts "\nCanceled."
  end

  def cmd_delete
    confirmed = @prompt.select(
      "Delete \"#{@session.name}\"?",
      [{ name: 'No',  value: false }, { name: 'Yes', value: true }],
      cycle: false
    )
    return unless confirmed

    file = @session.file_path

    # Delete the file if it exists
    if File.exist?(file)
      File.delete(file)
      puts @pastel.yellow("✓ Deleted: #{@session.name}")
    end

    # Build choices: "new chat" first, then remaining sessions
    remaining = ChatSession.list_files
    choices   = [{ name: @pastel.green('+ New chat'), value: :new }]
    choices  += remaining.map do |f|
      begin
        data  = JSON.parse(File.read(f), symbolize_names: true)
        name  = data[:name]  || File.basename(f, '.json')
        mname = data[:model_name] || data[:model_id] || '?'
        count = (data[:messages] || []).length
        saved = data[:saved_at] ? Time.parse(data[:saved_at]).strftime('%Y-%m-%d %H:%M') : '?'
        label = "#{name}  #{@pastel.dim("│ #{mname} · #{count} msg · #{saved}")}"
        { name: label, value: f }
      rescue
        { name: File.basename(f, '.json'), value: f }
      end
    end

    selected = @prompt.select(
      'Open a session:',
      choices,
      per_page: [choices.length, 16].min,
      cycle:    false
    )

    if selected == :new || selected.nil?
      @session = ChatSession.new(@model)
      puts @pastel.green("✓ New chat session: #{@session.name}")
    else
      loaded = ChatSession.load_from_file(selected, MODELS)
      if loaded
        @session = loaded
        @model   = loaded.model
        puts @pastel.green("✓ Loaded: #{loaded.name}")
        puts @pastel.dim("  Model: #{loaded.model[:name]} · #{loaded.message_count} message(s)")
        show_recent_messages(loaded) if loaded.message_count > 0
        puts
      else
        puts @pastel.red('Failed to load session — starting a new one.')
        @session = ChatSession.new(@model)
      end
    end
  rescue TTY::Reader::InputInterrupt, Interrupt
    # Cancelled the picker after deletion — just start fresh
    @session = ChatSession.new(@model)
    puts @pastel.green("✓ New chat session: #{@session.name}")
  end

  # ── OpenAI call ───────────────────────────────────────────────────────────

  def send_message(text)
    return if text.nil? || text.strip.empty?

    @input_history << text
    @history_pos = nil
    @session.add_message('user', text)

    spinner = TTY::Spinner.new(
      "  #{@pastel.dim('[:spinner] Thinking…')}",
      format: :dots,
      clear:  true,
      output: $stderr
    )
    spinner.auto_spin

    begin
      reply = call_openai
      spinner.stop
    rescue StandardError => e
      spinner.stop
      @session.messages.pop   # remove the user message we optimistically added
      # re-save without it
      @session.save
      puts @pastel.red("\n  API error: #{e.message}\n")
      return
    end

    rendered = TTY::Markdown.parse(reply)
    puts "\n#{@pastel.green.bold('Assistant:')}\n#{rendered}"
    @session.add_message('assistant', reply)
  end

  def call_openai
    if @model[:responses_api]
      call_responses_api
    else
      call_chat_completions_api
    end
  end

  # ── Responses API (stateful — uses previous_response_id) ─────────────────

  def call_responses_api
    model_id      = @model[:id]
    use_websearch = @model[:web_search_capable] && @session.web_search_enabled
    last_id       = @session.last_response_id
    new_msg       = @session.messages.last[:content]

    params = { model: model_id }

    if last_id
      # Continue the server-side conversation — only send the new user message.
      params[:previous_response_id] = last_id
      params[:input]                = new_msg
    else
      # First turn (or no stored ID): send full history so the model has context.
      params[:input] = @session.messages.map { |m| { role: m[:role], content: m[:content] } }
    end

    params[:tools] = [{ type: 'web_search_preview' }] if use_websearch

    # o-series reasoning models don't accept temperature
    params[:temperature] = 0.7 unless model_id.match?(/\Ao[1-9]/)

    with_rate_limit_retry do
      response = @client.responses.create(parameters: params)

      if response['error']
        msg  = response.dig('error', 'message').to_s
        code = response.dig('error', 'code').to_s
        # If the previous_response_id has expired, clear it and retry with full history
        if last_id && (code == 'invalid_value' || msg.include?('previous_response_id'))
          @session.last_response_id = nil
          params.delete(:previous_response_id)
          params[:input] = @session.messages.map { |m| { role: m[:role], content: m[:content] } }
          response = @client.responses.create(parameters: params)
        end
        raise response.dig('error', 'message').to_s if response['error']
      end

      # Store the new response ID for the next turn
      @session.last_response_id = response['id']

      # Extract the assistant text from the output array
      output = response['output']
      raise 'Empty response from API' unless output&.any?

      message_item = output.find { |item| item['type'] == 'message' }
      raise 'No message item in response' unless message_item

      content   = message_item['content']
      text_part = content&.find { |c| c['type'] == 'output_text' }
      raise 'No text in response' unless text_part

      text_part['text'].to_s.strip
    end
  end

  # ── Chat Completions API (stateless — sends full history each time) ───────

  def call_chat_completions_api
    model_id = if @model[:web_search_capable] &&
                    @session.web_search_enabled &&
                    @model[:search_id]
                 @model[:search_id]
               else
                 @model[:id]
               end

    params = {
      model:    model_id,
      messages: @session.messages
    }

    params[:temperature] = 0.7 unless model_id.match?(/\Ao[1-9]|search-preview/)

    with_rate_limit_retry do
      response = @client.chat(parameters: params)

      if response['error']
        raise response.dig('error', 'message').to_s
      end

      choices = response['choices']
      raise 'Empty response from API' unless choices&.any?

      choices.first.dig('message', 'content').to_s.strip
    end
  end

  # ── Shared retry wrapper for 429 rate-limit errors ────────────────────────

  def with_rate_limit_retry(max_retries: 4, base_delay: 5)
    max_retries.times do |attempt|
      return yield
    rescue Faraday::TooManyRequestsError => e
      raise e if attempt == max_retries - 1
      wait = base_delay * (2**attempt)
      $stderr.puts @pastel.yellow("\n  Rate limited — retrying in #{wait}s… (attempt #{attempt + 1}/#{max_retries})")
      sleep wait
    rescue StandardError => e
      raise unless e.message.include?('429') || e.message.include?('Rate limit')
      raise e if attempt == max_retries - 1
      wait = base_delay * (2**attempt)
      $stderr.puts @pastel.yellow("\n  Rate limited — retrying in #{wait}s… (attempt #{attempt + 1}/#{max_retries})")
      sleep wait
    end
  end
end

