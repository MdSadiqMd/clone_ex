# Use the official Elixir image
FROM elixir:1.18-slim

# Install required system dependencies
RUN apt-get update && apt-get install -y \
    git \
    tar \
    zstd \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Copy mix files first for dependency caching
COPY mix.exs mix.lock ./

# Install Hex and Rebar
RUN mix local.hex --force && mix local.rebar --force

# Get dependencies
RUN mix deps.get

# Copy the rest of the application
COPY . .

# Build the escript
RUN mix escript.build

# Make the escript executable
RUN chmod +x clone_ex

# Default command (can be overridden with docker run args)
CMD ["./clone_ex", "--help"]
