ARG DOTNET_SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:10.0
ARG DOTNET_RUNTIME_IMAGE=mcr.microsoft.com/dotnet/aspnet:10.0

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

ENV ASPNETCORE_URLS=http://+:80
EXPOSE 80

# https://github.com/hexops-graveyard/dockerfile#do-not-use-a-uid-below-10000
RUN groupadd -g 10001 app && \
    useradd -r -u 10001 -g app app

COPY --from=build /app/publish ./
RUN chown -R app:app .

USER app
ENTRYPOINT ["dotnet", "backend.dll"]
