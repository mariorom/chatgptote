# ChatGPTote 🤖

A terminal ChatGPT client written in Ruby.

## Requirements

- Ruby 3.0+
- Bundler (`gem install bundler`)
- An OpenAI API key

## Setup

```bash
cd chatgptote
bundle install
export OPENAI_ACCESS_TOKEN=sk-...
```

## Run

```bash
bundle exec ruby chatgptote.rb
# or, after chmod +x:
./chatgptote.rb
```

## Usage

### Model selection
On startup you'll see a scrollable list of models (↑↓ arrows, Enter to confirm).  
Models marked **🔍 web search** support live internet lookups.

### Prompt
The prompt shows your active model and web-search status:

```
gpt-4o 🔍on ❯ _
gpt-4o 🔍off ❯ _
o1 ❯ _
```

### Commands
Type `/` to open the command picker — a live-filtered dropdown similar to IRB.  
Start typing letters to filter, use ↑↓ to navigate, Enter to run, Esc to cancel.

| Command              | Description                                       |
|----------------------|---------------------------------------------------|
| `/list`              | Show all available models with prices             |
| `/help`              | Show this command list                            |
| `/exit`              | Save and quit                                     |
| `/enable_websearch`  | Enable web search (requires a compatible model)   |
| `/disable_websearch` | Disable web search                                |
| `/clear`             | Clear the terminal                                |
| `/new`               | Start a fresh chat session                        |
| `/name`              | Rename the current session                        |
| `/chats`             | Browse saved sessions and load one                |

### Keyboard shortcuts
- `Ctrl-C` — save and exit
- `Backspace` — delete last character

## Chat storage

Every conversation is automatically saved to `chats/YYYYMMDD_HHMMSS.json`.  
The last session is restored automatically when you restart the app.

## Web search

Only `gpt-4o` and `gpt-4o-mini` support web search.  
When enabled, the app uses OpenAI's `-search-preview` model variants  
(`gpt-4o-search-preview` / `gpt-4o-mini-search-preview`) which include  
real-time internet results grounded in the response.

