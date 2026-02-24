# Backend

To start a backend:

```sh
docker compose up
```

To run locally:

```sh
dotnet run --project server
```

To test:

```sh
dotnet test
```

## Setup diary

Got copilot to set up some of the scaffolding.

Chose `-noble` as that is the latest microsoft ubuntu image, and I don't want to install the things I use all the time (eg. alpine).

Learned about `dotnet sln` for generating solution and project files.

Added a test to make sure we can test it.

We need to serve the app from the root as well, that will be the web version.
