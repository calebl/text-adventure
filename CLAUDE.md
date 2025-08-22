# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Text Adventure is a Rails 8 API-only application that creates AI-powered text-based adventure games. It uses the Raix gem to interact with AI models through OpenRouter, specifically the `cognitivecomputations/dolphin-mixtral-8x22b` model for generating narrative content.

## Development Environment

- **Ruby**: 3.3.5 (managed by asdf/rbenv, see `.tool-versions`)
- **Node.js**: 18.19.0
- **Rails**: 8.0.0 (API-only mode)
- **Database**: SQLite3 for development
- **Graph Database**: Neo4j integration via activegraph gem (currently commented out in application.rb)

## Key Dependencies

- **raix** (~> 0.4.8): AI chat completion framework
- **open_router** (~> 0.3.3): OpenRouter API client for accessing AI models
- **activegraph** (~> 11.4): Neo4j integration for story graph storage
- **solid_cache/solid_queue/solid_cable**: Rails 8 solid adapters

## Common Commands

### Development
```bash
# Install dependencies
bundle install

# Start Rails server
rails server

# Run interactive narrator chatbot
rake narrator:interact

# Rails console
rails console
```

### Testing
```bash
# Run all tests
rails test

# Run specific test
rails test test/models/narrator_test.rb
```

### Code Quality
```bash
# Run rubocop (Rails omakase style)
bundle exec rubocop

# Run security scanner
bundle exec brakeman
```

## Architecture

### Core Components

1. **Narrator Model** (`app/models/narrator.rb`): 
   - Primary AI interaction class using Raix::ChatCompletion
   - Manages conversation transcript and system directives
   - Configured for choose-your-own-adventure style narratives

2. **AI Configuration**:
   - OpenRouter API integration in `config/initializers/open_router.rb`
   - Raix configuration in `config/initializers/raix.rb`  
   - API credentials stored in Rails encrypted credentials

3. **Interactive Interface**:
   - Command-line interaction via `rake narrator:interact`
   - Loops for continuous conversation with AI narrator

### System Architecture

- **API-only Rails app** with no frontend views
- **Neo4j integration** planned for story graph persistence (currently disabled)
- **AI-driven narrative generation** with rule-based constraints
- **Conversation state management** through transcript arrays

### Configuration Notes

- OpenRouter access token must be configured: `rails credentials:edit` and add `open_router: { access_token: "your_token" }`
- Neo4j integration is currently commented out in `config/application.rb` but gems are installed
- Application configured as API-only but can be extended with web interface

### Development Workflow

The main development interface is through the rake task `narrator:interact` which provides a command-line chat interface with the AI narrator. The narrator follows specific rules for adventure game mechanics including preventing unrealistic actions and maintaining narrative flow.