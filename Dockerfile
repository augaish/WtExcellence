FROM ruby:3.4.5 as base

# Headless Chromium prints the governed documents to PDF on publication.
ENV CHROMIUM_BIN=/usr/bin/chromium

RUN apt-get update -qq && apt-get install -y \
  build-essential \
  apt-utils \
  libpq-dev \
  nodejs \
  curl \
  bash \
  libvips \
  npm \
  git \
  tesseract-ocr \
  tesseract-ocr-eng \
  tesseract-ocr-ara \
  poppler-utils \
  chromium \
  fonts-noto-core \
  openssh-client \
  default-jre && \
  # Install Apache Tika (using Maven Central for reliability)
  TIKA_VERSION=3.0.0 && \
  curl -L -o /tmp/tika-app.jar "https://repo1.maven.org/maven2/org/apache/tika/tika-app/${TIKA_VERSION}/tika-app-${TIKA_VERSION}.jar" && \
  mkdir -p /opt/tika && \
  mv /tmp/tika-app.jar /opt/tika/tika-app.jar && \
  echo '#!/bin/bash\njava -jar /opt/tika/tika-app.jar "$@"' > /usr/local/bin/tika && \
  chmod +x /usr/local/bin/tika && \
  rm -rf /var/lib/apt/lists/* 

WORKDIR /docker/app

RUN gem install bundler

COPY Gemfile* ./

# Install gems with Linux platform support for Tailwind CSS
RUN bundle lock --add-platform x86_64-linux && \
    bundle lock --add-platform aarch64-linux && \
    bundle install

COPY package*.json ./

RUN npm install --include=dev

ADD . /docker/app

COPY template/database.yml config/database.yml

# Build Tailwind CSS for production (allow failure so build can proceed)
RUN SECRET_KEY_BASE=1 RAILS_ENV=production bundle exec rails tailwindcss:build || echo "Tailwind CSS build failed; continuing Docker build"

# Ensure Tailwind build artifact exists (fallback)
RUN if [ ! -s app/assets/builds/tailwind.css ]; then \
      mkdir -p app/assets/builds app/assets/tailwind && \
      cp template/application.css app/assets/tailwind/application.css && \
      npx tailwindcss -i app/assets/tailwind/application.css -o app/assets/builds/tailwind.css --minify; \
    fi

# Precompile assets for production
RUN SECRET_KEY_BASE=1 RAILS_ENV=production bundle exec rails assets:precompile



ENTRYPOINT ["./docker-entrypoint.sh"]
EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]