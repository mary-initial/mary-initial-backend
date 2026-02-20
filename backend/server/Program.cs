using Mary.Server.Schema;
using GraphQL;
using GraphQL.Types;

var builder = WebApplication.CreateBuilder(args);

var schema = new Schema { Query = new Query() };
builder.Services.AddGraphQL(b => b.AddSchema(schema).AddSystemTextJson());

var app = builder.Build();
app.UseDeveloperExceptionPage();
app.UseGraphQL("/api/graphql");
app.UseGraphQLGraphiQL("/", new GraphQL.Server.Ui.GraphiQL.GraphiQLOptions
{
    GraphQLEndPoint = "/api/graphql",         // url of GraphQL endpoint
    // SubscriptionsEndPoint = "/api/graphql",   // url of GraphQL endpoint
});
await app.RunAsync();
