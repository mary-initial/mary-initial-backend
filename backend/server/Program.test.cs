using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Mary.Server.Tests;

public class GraphQLTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public GraphQLTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GreetingQuery_ReturnsHelloWorld()
    {
        var payload = new { query = "{ greeting { message } }" };

        var response = await _client.PostAsJsonAsync("/api/graphql", payload);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();

        Assert.True(json.TryGetProperty("data", out var data));
        Assert.True(data.TryGetProperty("greeting", out var greeting));
        Assert.True(greeting.TryGetProperty("message", out var message));
        Assert.Equal("Hello, World!", message.GetString());
    }
}
