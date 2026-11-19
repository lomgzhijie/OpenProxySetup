using System;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using System.Text;

class FakeLogin : HttpMessageHandler {
    internal string Mode;
    internal int ProtectedRequests;
    internal FakeLogin(string mode){Mode=mode;}
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token){
        if(request.RequestUri.Scheme!="https"||request.RequestUri.Host!="example.test")throw new Exception("Unexpected origin");
        if(request.Method==HttpMethod.Post){
            if(request.Headers.Contains("Cookie"))throw new Exception("Old cookie included in password verification");
            if(!(await request.Content.ReadAsStringAsync()).Contains("password=test-password"))throw new Exception("Password form");
            if(Mode=="redirect")return new HttpResponseMessage(HttpStatusCode.Redirect){Headers={Location=new Uri("https://other.test/")}};
            var response=new HttpResponseMessage(HttpStatusCode.OK);
            response.Content=new StringContent(Mode=="wrong"?"<html>login</html>":"{\"success\":true}",Encoding.UTF8,Mode=="wrong"?"text/html":"application/json");
            if(Mode!="missing-cookie")response.Headers.Add("Set-Cookie","auth=fresh-token; Path=/; Secure; HttpOnly");
            return response;
        }
        ProtectedRequests++;
        if(!request.Headers.GetValues("Cookie").GetEnumerator().MoveNext())throw new Exception("New auth cookie missing");
        return new HttpResponseMessage(Mode=="invalid-cookie"?HttpStatusCode.Unauthorized:HttpStatusCode.OK){Content=new StringContent("{\"UUID\":\"test-id\"}",Encoding.UTF8,"application/json")};
    }
}
class SiteAuthTests {
    static void Main(){Run().GetAwaiter().GetResult();}
    static async Task Run(){
        foreach(string mode in new[]{"wrong","redirect","missing-cookie","invalid-cookie"}){
            var fake=new FakeLogin(mode);bool failed=false;
            try{await OpenProxySetupSiteAuth.Verify("https://example.test/admin","test-password","QA-UA",fake);}catch(InvalidOperationException){failed=true;}
            if(!failed)throw new Exception("Accepted "+mode);
            if(mode!="invalid-cookie"&&fake.ProtectedRequests!=0)throw new Exception("Protected page requested before password accepted");
        }
        var good=new FakeLogin("correct");
        if(await OpenProxySetupSiteAuth.Verify("https://example.test/admin","test-password","QA-UA",good)!="fresh-token"||good.ProtectedRequests!=1)throw new Exception("Successful login");
        Console.WriteLine("PASS fresh-cookie password verification, wrong password, redirects, missing cookie, protected resource, successful login");
    }
}
