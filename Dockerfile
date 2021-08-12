FROM jupyter/base-notebook:latest

# Install .NET CLI dependencies

ARG NB_USER=jovyan
ARG NB_UID=1000
ENV USER ${NB_USER}
ENV NB_UID ${NB_UID}
ENV HOME /home/${NB_USER}

WORKDIR ${HOME}

USER root
RUN apt-get update
RUN apt-get install -y curl

ENV \
    # Enable detection of running in a container
    DOTNET_RUNNING_IN_CONTAINER=true \
    # Enable correct mode for dotnet watch (only mode supported in a container)
    DOTNET_USE_POLLING_FILE_WATCHER=true \
    # Skip extraction of XML docs - generally not useful within an image/container - helps performance
    NUGET_XMLDOC_MODE=skip \
    # Opt out of telemetry until after we install jupyter when building the image, this prevents caching of machine id
    DOTNET_INTERACTIVE_CLI_TELEMETRY_OPTOUT=true

# Install .NET CLI dependencies
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libc6 \
        libgcc1 \
        libgssapi-krb5-2 \
        libicu66 \
        libssl1.1 \
        libstdc++6 \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Install .NET Core SDK

# When updating the SDK version, the sha512 value a few lines down must also be updated.
ENV DOTNET_SDK_VERSION 5.0.102

RUN dotnet_sdk_version=5.0.102 \
    && curl -SL --output dotnet.tar.gz https://dotnetcli.azureedge.net/dotnet/Sdk/$dotnet_sdk_version/dotnet-sdk-$dotnet_sdk_version-linux-x64.tar.gz \
    && dotnet_sha512='0ce2d5365ca39808fb71baec4584d4ec786491c3735543dc93244604ea97e242377d0987cd8b1e529258dee68f203b5780559201e7ea6d84487d6d8d433329b3' \
    && echo "$dotnet_sha512 dotnet.tar.gz" | sha512sum -c - \
    && mkdir -p /usr/share/dotnet \
    && tar -ozxf dotnet.tar.gz -C /usr/share/dotnet \
    && rm dotnet.tar.gz \
    && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
    # Trigger first run experience by running arbitrary cmd
    && dotnet help

# Copy notebooks
COPY ./ ${HOME}/Notebooks/

# Add package sources
RUN echo "\
<configuration>\
  <solution>\
    <add key=\"disableSourceControlIntegration\" value=\"true\" />\
  </solution>\
  <packageSources>\
    <clear />\
    <add key=\"ServiceStack MyGet feed\" value=\"https://www.myget.org/F/servicestack\" />\
    <add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" protocolVersion=\"3\" />\
  </packageSources>\
  <disabledPackageSources />\
</configuration>\
" > ${HOME}/NuGet.config

RUN echo "\
<Project Sdk=\"Microsoft.NET.Sdk.Web\">\
  <PropertyGroup>\
    <TargetFramework>net5.0</TargetFramework>\
  </PropertyGroup>\
  <ItemGroup>\
    <PackageReference Include=\"ServiceStack\" Version=\"5.*\" />\
    <PackageReference Include=\"Plotly.NET.Interactive\" Version=\"2.0.0-preview.6\" />\
  </ItemGroup>\
</Project>\
" > ${HOME}/preload.csproj

RUN chown -R ${NB_UID} ${HOME}
USER ${USER}

#Install nteract 
RUN pip install nteract_on_jupyter

# Install lastest build from main branch of Microsoft.DotNet.Interactive
RUN dotnet tool install -g Microsoft.dotnet-interactive

# Install the ServiceStack `x` tool
RUN dotnet tool install -g x

# Pre-install packages
RUN dotnet restore ${HOME}/preload.csproj

ENV PATH="${PATH}:${HOME}/.dotnet/tools"
RUN echo "$PATH"

# Install kernel specs
RUN dotnet interactive jupyter install

# Enable telemetry once we install jupyter for the image
ENV DOTNET_INTERACTIVE_CLI_TELEMETRY_OPTOUT=false

# Set root to Notebooks
WORKDIR ${HOME}/Notebooks/
