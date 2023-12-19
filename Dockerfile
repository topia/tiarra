FROM perl:5.38.2-threaded
MAINTAINER Topia <topia@clovery.jp>

RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends locales runit && \
    echo ja_JP.UTF-8 UTF-8 >> /etc/locale.gen && \
    locale-gen && apt-get clean

RUN \
    cpanm -v --installdeps IO::Socket::INET6 && \
    cpanm -v --notest IO::Socket::INET6 && \
    cpanm -v Socket6 IO::Socket::SSL Unicode::Japanese enum HTTP::Request LWP::Protocol::https

WORKDIR /tiarra
COPY . /tiarra/
RUN perl ./makedoc > /dev/null
ENTRYPOINT ["/tiarra/docker-startup.sh"]
