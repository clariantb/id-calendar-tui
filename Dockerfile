FROM ruby:3.3-slim

WORKDIR /app

# Install dependencies
COPY Gemfile Gemfile.lock *.gemspec ./
RUN bundle install --without development test

# Copy the app
COPY lib ./lib
COPY bin ./bin
COPY data ./data
COPY README.md LICENSE ./

# Install the gem locally
RUN gem build *.gemspec && gem install *.gem

# Run the calendar
CMD ["calendar"]