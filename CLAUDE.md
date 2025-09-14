# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is `msg`, an Elixir library for accessing Microsoft 365 data using the Microsoft Graph API. It's designed specifically for applications using OAuth2 client credentials flow (application-only authentication).

## Development Commands

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run tests with coverage
mix coveralls

# Format code
mix format

# Generate documentation (docs environment)
mix docs

# Run comprehensive quality checks
mix quality

# Skip slow Dialyzer step in quality check
mix quality --skip-dialyzer

# Run static analysis only
mix credo --strict

# Run type checking
mix dialyzer

# Run a single test file
mix test test/path/to/test_file.exs

# Run integration tests
mix test test/msg/integration/
```

## Quality Standards

This project enforces strict code quality via the `mix quality` task (`lib/mix/tasks/quality.ex:1`), which runs:

- Code formatting (auto-fixed)
- Trailing whitespace removal (auto-fixed)
- Markdown linting (auto-fixed if markdownlint-cli2 available)
- Test coverage check (requires >90%)
- Static analysis with Credo in strict mode
- Type checking with Dialyzer

## Architecture

The library follows a layered architecture:

- **Msg.Client** (`lib/msg/client.ex:1`): Handles OAuth2 authentication and creates configured Req clients with Bearer tokens for Graph API requests
- **Msg.Request** (`lib/msg/request.ex:1`): Provides low-level HTTP request helpers with response handling and error parsing
- **Msg.Users** (`lib/msg/users.ex:1`): Higher-level API wrapper for `/users` endpoints - pattern for other Graph API modules

### Key Dependencies

- **Req**: HTTP client for making API requests
- **OAuth2**: Client credentials flow implementation
- **Jason**: JSON encoding/decoding
- **Mox**: Test mocking framework
- **Credo**: Static code analysis
- **Dialyzer**: Type checking
- **ExCoveralls**: Test coverage reporting

### Testing Strategy

The project uses ExUnit with Mox for mocking. Integration tests are separated in `test/msg/integration/` directory for real API testing scenarios. Coverage must be >90%.

### Authentication Flow

The library implements OAuth2 client credentials flow:
1. `Msg.Client.new/1` accepts credentials (`client_id`, `client_secret`, `tenant_id`)
2. `fetch_token!/1` exchanges credentials for access token via Azure AD
3. Returns configured Req client with Authorization header for Graph API calls