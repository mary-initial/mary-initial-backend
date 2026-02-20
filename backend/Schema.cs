using GraphQL;
using GraphQL.Types;

namespace Mary.Backend.Schema
{
    public class Query : ObjectGraphType
    {
        public Query()
        {
            Field<GreetingType>("greeting")
                .Description("Returns a greeting message. Used to test that the integration works.")
                .Resolve(context => new Greeting { Message = "Hello, World!" });
        }
    }

    public struct Greeting
    {
        public string Message { get; set; }
    }

    public class GreetingType : ObjectGraphType<Greeting>
    {
        public GreetingType()
        {
            Field(x => x.Message).Description("The greeting message");
        }
    }
}