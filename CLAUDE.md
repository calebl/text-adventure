# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Text Adventure is a Rails 8 API-only application that creates AI-powered text-based adventure games. It uses the RubyLLM gem to interact with AI models through OpenRouter, specifically the `cognitivecomputations/dolphin-mixtral-8x22b` model for generating narrative content.

## Development Environment

- **Ruby**: 3.3.5 (managed by asdf, see `.tool-versions`)
- **Node.js**: 18.19.0
- **Rails**: 8.0.0 (API-only mode)
- **Database**: SQLite3 for development and production

## Key Dependencies

- **ruby_llm**: AI chat completion framework with OpenRouter integration
- **open_router** (~> 0.3.3): OpenRouter API client for accessing AI models
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
   - Primary AI interaction class using RubyLLM chat interface
   - Manages conversation state through RubyLLM chat objects
   - Configured for choose-your-own-adventure style narratives

2. **AI Configuration**:
   - RubyLLM configuration in `config/initializers/ruby_llm.rb`
   - OpenRouter API key configured via environment variable `OPENROUTER_API_KEY`
   - Default model set to `mistralai/mistral-medium-3.1`

3. **Interactive Interface**:
   - Command-line interaction via `rake narrator:interact`
   - Loops for continuous conversation with AI narrator

### System Architecture

- **API-only Rails app** with no frontend views
- **AI-driven narrative generation** with rule-based constraints
- **Conversation state management** through RubyLLM chat objects and database persistence
- **Database models** for Chat, Message, and ToolCall to store conversation history

### Configuration Notes

- OpenRouter API key must be set as environment variable: `OPENROUTER_API_KEY=your_token`
- Neo4j integration is currently commented out in `config/application.rb` but gems are installed
- Application configured as API-only but can be extended with web interface

### Development Workflow

The main development interface is through the rake task `narrator:interact` which provides a command-line chat interface with the AI narrator. The narrator follows specific rules for adventure game mechanics including preventing unrealistic actions and maintaining narrative flow.

### Model updates
- whenever a model is updated, check the model tests and factories and make the appropriate updates in those as well

### Testing Requirements

#### Model Coverage
- **Every model MUST have a corresponding test file** in `test/models/`
- **Every model MUST have a factory** in `test/factories/`
- Test files should cover all validations, associations, scopes, and public methods
- Use descriptive test names that explain the expected behavior

#### Factory Requirements
- Factories should provide valid default attributes for all required fields
- Use traits for common variations (e.g. `:rivendell` location, `:elrond` character)
- Ensure factories create valid objects that pass all model validations
- Keep factories minimal but complete - only specify what's necessary for a valid object

#### Database Schema
The current database includes the following story-related models with proper associations:
- **Story** → **Characters**, **Locations**, **Scenes**
- **Scene** → belongs to **Location**, has many **Characters** through join table
- **Interaction** → belongs to **Character**, **Scene**, and **Location**
- **Location** → tracks `last_protagonist_visit` timestamp updated via Scene callbacks

- All interactions with AI LLMs should use a structured output with RubyLLM::Schema