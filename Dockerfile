# docker build -f Dockerfile -t cuprite .

FROM ubuntu:16.04

ARG ruby=2.3.7

RUN apt-get update

RUN apt-get install -y wget
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -
RUN echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list

RUN apt-get update

# Dependencies for ruby
RUN apt-get install -y locales build-essential zlib1g-dev libffi-dev libssl-dev libreadline6-dev libyaml-dev libcurl4-openssl-dev git google-chrome-stable google-chrome-beta chromium-browser locales unzip

RUN wget -O /root/chrome-linux.zip https://download-chromium.appspot.com/dl/Linux_x64?type=snapshots
RUN unzip /root/chrome-linux.zip && rm /root/chrome-linux.zip

# Set the locale
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Install ruby
RUN git clone https://github.com/sstephenson/rbenv.git /root/.rbenv
RUN git clone https://github.com/sstephenson/ruby-build.git /root/.rbenv/plugins/ruby-build
ENV PATH /root/.rbenv/bin:$PATH
RUN echo 'eval "$(rbenv init -)"' >> /etc/profile.d/rbenv.sh # or /etc/profile
RUN echo 'eval "$(rbenv init -)"' >> /root/.bashrc
ENV CONFIGURE_OPTS --disable-install-doc
RUN rbenv install $ruby
RUN rbenv global $ruby
RUN rbenv rehash
RUN echo "gem: --no-ri --no-rdoc" > /root/.gemrc && chmod 644 /root/.gemrc
RUN rbenv exec gem install bundler --conservative
RUN rbenv exec bundle config git.allow_insecure true

RUN git clone https://github.com/machinio/cuprite.git /root/cuprite
WORKDIR /root/cuprite
RUN rbenv exec bundle install
