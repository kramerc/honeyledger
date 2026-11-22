# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.10
# Temporarily built from a fork: upstream rails/devcontainer added Ruby 4.0.10
# but has not tagged the ruby-2.3.7 release that publishes its image
# (rails/devcontainer issue 142). Switch back to
# ghcr.io/rails/devcontainer/images/ruby once that tag is published.
FROM ghcr.io/kramerc/rails-devcontainer/images/ruby:$RUBY_VERSION

# Ensure binding is always 0.0.0.0
# Binds the server to all IP addresses of the container, so it can be accessed from outside the container.
ENV BINDING="0.0.0.0"
