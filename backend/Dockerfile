ARG DOTNET_SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:10.0-noble
ARG DOTNET_RUNTIME_IMAGE=mcr.microsoft.com/dotnet/aspnet:10.0-noble

FROM ${DOTNET_SDK_IMAGE} AS build
WORKDIR /src

# Copy csproj and restore first for better caching
COPY ["backend.csproj", "./"]
RUN dotnet restore "./backend.csproj"

# Copy the rest and publish
COPY . .
RUN dotnet publish "backend.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM ${DOTNET_RUNTIME_IMAGE} AS runtime
WORKDIR /app

# https://github.com/hexops-graveyard/dockerfile#do-not-use-a-uid-below-10000
RUN groupadd -g 10001 mary-app && \
    useradd -r -u 10001 -g mary-app mary-app

COPY --from=build /app/publish ./
RUN chown -R mary-app:mary-app .

USER mary-app
ENTRYPOINT ["dotnet", "backend.dll"]