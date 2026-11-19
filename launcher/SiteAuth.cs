using System;
using System.Linq;
using System.Net.Http;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Collections.Generic;

public static class OpenProxySetupSiteAuth
{
    public static async Task<string> Verify(string address,string password,string userAgent,HttpMessageHandler testHandler=null)
    {
        Uri uri;
        if (!Uri.TryCreate(address,UriKind.Absolute,out uri)||uri.Scheme!="https"||uri.UserInfo.Length!=0||String.IsNullOrEmpty(password))
            throw new InvalidOperationException("请输入站点网址和后台密码。");
        string origin=uri.GetLeftPart(UriPartial.Authority);
        System.Net.ServicePointManager.SecurityProtocol |= System.Net.SecurityProtocolType.Tls12;
        var handler=testHandler??new HttpClientHandler {AllowAutoRedirect=false,UseCookies=false};
        using(var client=new HttpClient(handler)) {
            client.Timeout=TimeSpan.FromSeconds(20);client.MaxResponseContentBufferSize=2*1024*1024;
            client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent",userAgent);
            client.DefaultRequestHeaders.TryAddWithoutValidation("Accept","application/json");
            using(var post=new HttpRequestMessage(HttpMethod.Post,origin+"/login")) {
                post.Content=new FormUrlEncodedContent(new[]{new KeyValuePair<string,string>("password",password)});
                using(var response=await client.SendAsync(post)) {
                    int code=(int)response.StatusCode;
                    if(code==401||code==403)throw new InvalidOperationException("密码不正确，或站点限制了登录访问。请检查后重试。");
                    if(code!=200)throw new InvalidOperationException(code>=300&&code<400?"站点登录发生重定向，请检查网址。":"站点暂时无法验证，请稍后重试。");
                    if(!IsJson(response))throw new InvalidOperationException("密码不正确，请重新输入。");
                    Dictionary<string,object> result;
                    try {result=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(await response.Content.ReadAsStringAsync());}
                    catch {throw new InvalidOperationException("站点返回了无效的登录结果。");}
                    if(result==null||!result.ContainsKey("success")||!Object.Equals(result["success"],true))throw new InvalidOperationException("密码不正确，请重新输入。");
                    IEnumerable<string> values;
                    string cookie=response.Headers.TryGetValues("Set-Cookie",out values)?values.FirstOrDefault(v=>v.StartsWith("auth=",StringComparison.Ordinal)):null;
                    if(cookie==null)throw new InvalidOperationException("站点未返回有效的登录凭据。");
                    cookie=cookie.Split(';')[0];
                    if(cookie.Length<=5||cookie.Contains("\r")||cookie.Contains("\n"))throw new InvalidOperationException("站点未返回有效的登录凭据。");
                    using(var check=new HttpRequestMessage(HttpMethod.Get,origin+"/admin/config.json")) {
                        check.Headers.TryAddWithoutValidation("Cookie",cookie);
                        using(var protectedResponse=await client.SendAsync(check)) {
                            if(protectedResponse.StatusCode!=System.Net.HttpStatusCode.OK||!IsJson(protectedResponse))
                                throw new InvalidOperationException("后台登录验证未通过，请检查密码。");
                            Dictionary<string,object> config;
                            try {config=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(await protectedResponse.Content.ReadAsStringAsync());}
                            catch {throw new InvalidOperationException("站点返回了无效的后台数据。");}
                            if(config==null||!config.ContainsKey("UUID")||String.IsNullOrEmpty(config["UUID"] as string))
                                throw new InvalidOperationException("站点不是受支持的管理后台。");
                        }
                    }
                    return cookie.Substring(5);
                }
            }
        }
    }
    private static bool IsJson(HttpResponseMessage r) {
        return r.Content.Headers.ContentType!=null&&String.Equals(r.Content.Headers.ContentType.MediaType,"application/json",StringComparison.OrdinalIgnoreCase);
    }
}
