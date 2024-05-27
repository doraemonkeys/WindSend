FROM mcr.microsoft.com/devcontainers/universal:2

# [Optional] Uncomment this section to install additional OS packages.
RUN rm -rf /var/lib/apt/lists/* \
    && apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install clang lld \
    && apt-get autoremove -y && apt-get clean -y \
    && sudo apt-get install -y libgtk-3-dev libxdo-dev libappindicator3-dev


RUN useradd -m ricky
USER ricky

# https://stackoverflow.com/questions/72420361/how-to-run-flutter-on-the-github-codespaces-like-as-run-it-on-my-desktop
RUN apt-get update && apt-get -y install git curl unzip

RUN  mkdir -p /workspaces/dart
WORKDIR /workspaces/dart

ENV PUB_CACHE=/workspaces/dart/.pub_cache
ENV PATH="/workspaces/dart/flutter/bin:$PATH"

RUN whoami

RUN git clone https://github.com/flutter/flutter -b stable --depth 1
RUN git config --global --add safe.directory /workspaces/dart/flutter
# flutter不推荐在 root 用户下运行 flutter upgrade，可能会带来安全风险，并且可能会影响文件权限
RUN flutter upgrade
RUN flutter config --enable-web

RUN touch /workspaces/testdir

# [Optional] Uncomment the next lines to use go get to install anything else you need
# USER vscode
# RUN go get -x <your-dependency-or-tool>
# USER root

# [Optional] Uncomment this line to install global node packages.
# RUN su vscode -c "source /usr/local/share/nvm/nvm.sh && npm install -g <your-package-here>" 2>&1
