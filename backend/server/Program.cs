using Mary.Server.Schema;
using GraphQL;
using GraphQL.Types;

var builder = WebApplication.CreateBuilder(args);

var schema = new Schema { Query = new Query() };
builder.Services.AddGraphQL(b => b.AddSchema(schema).AddSystemTextJson());

var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
var app = builder.Build();

app.UseDeveloperExceptionPage();

app.MapGet("/livez", () => Results.Ok(new { status = true }));
app.MapGet("/readyz", () => Results.Ok(new { status = true }));

app.UseGraphQL("/api/graphql");
app.UseGraphQLGraphiQL("/", new GraphQL.Server.Ui.GraphiQL.GraphiQLOptions
{
    GraphQLEndPoint = "/api/graphql",         // url of GraphQL endpoint
    // SubscriptionsEndPoint = "/api/graphql",   // url of GraphQL endpoint
});

await app.RunAsync();
